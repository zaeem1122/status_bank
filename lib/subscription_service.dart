import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class SubscriptionService {
  final InAppPurchase _iap = InAppPurchase.instance;
  ProductDetails? monthlyProduct;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Track purchase completion status
  final _purchaseCompleter = <String, Completer<PurchaseStatus>>{};

  // ✅ Global stream to notify all screens about subscription changes
  static final _subscriptionStatusController = StreamController<bool>.broadcast();
  static Stream<bool> get subscriptionStatusStream => _subscriptionStatusController.stream;

  // ✅ Background timer for periodic checks
  static Timer? _backgroundTimer;
  static int _checkCounter = 0;

  // ✅ Set to true during testing (5-min subscriptions), false for production (30-day subscriptions)
  static const bool isTestMode = true; // Change to false for production

  Future<void> init() async {
    final available = await _iap.isAvailable();
    if (!available) return;

    const ids = {"monthly"};
    ProductDetailsResponse response = await _iap.queryProductDetails(ids);

    if (response.productDetails.isNotEmpty) {
      monthlyProduct = response.productDetails.first;
    }

    await _subscription?.cancel();
    _subscription = _iap.purchaseStream.listen(_listenToPurchase);

    // 🔥 CRITICAL: Auto-restore on every app startup
    print('🚀 [init] AUTO-RESTORING subscription on app startup...');
    await autoRestoreOnStartup();

    // ✅ Start background checking when service initializes
    startBackgroundChecking();
  }

  // 🔥 NEW: Auto-restore purchases on every app startup
  static Future<void> autoRestoreOnStartup() async {
    try {
      print('🔄 [autoRestoreOnStartup] Starting automatic restore...');

      final prefs = await SharedPreferences.getInstance();
      final hadPremium = prefs.getBool("isPremium") ?? false;

      print('🔄 [autoRestoreOnStartup] Current local status: $hadPremium');

      // Clear local data to force fresh check with Play Store
      await prefs.remove("isPremium");
      await prefs.remove("subscriptionExpiry");

      // Check with Play Store
      final iap = InAppPurchase.instance;
      await iap.restorePurchases();

      // Wait for purchase listener to process
      final waitTime = isTestMode ? 3 : 5;
      await Future.delayed(Duration(seconds: waitTime));

      // Check final status after restore
      final isPremiumNow = await SubscriptionService.isPremium();

      print('🔄 [autoRestoreOnStartup] Status after Play Store check: $isPremiumNow');

      // Emit current status to all listeners
      _subscriptionStatusController.add(isPremiumNow);

      if (hadPremium && !isPremiumNow) {
        print('⚠️ [autoRestoreOnStartup] Subscription was cancelled/refunded/expired!');
      } else if (isPremiumNow) {
        print('✅ [autoRestoreOnStartup] Active subscription restored');
      } else {
        print('ℹ️ [autoRestoreOnStartup] No active subscription found');
      }
    } catch (e) {
      print('❌ [autoRestoreOnStartup] Error: $e');
      // On error, check local status and emit
      final localStatus = await SubscriptionService.isPremium();
      _subscriptionStatusController.add(localStatus);
    }
  }

  // 🔥 IMPROVED: Force immediate verification (called when app resumes)
  static Future<void> verifyNow() async {
    print('🔄 [verifyNow] ⚡ IMMEDIATE verification triggered');

    try {
      final prefs = await SharedPreferences.getInstance();
      final hadPremium = prefs.getBool("isPremium") ?? false;

      print('🔄 [verifyNow] Current status: $hadPremium');

      if (!hadPremium) {
        print('🔄 [verifyNow] User not premium, skipping Play Store check');
        _subscriptionStatusController.add(false);
        return;
      }

      // 🔥 CRITICAL: For premium users, ALWAYS verify with Play Store immediately
      print('🔄 [verifyNow] User is premium - verifying with Play Store NOW');

      final iap = InAppPurchase.instance;
      await iap.restorePurchases();

      // Wait for purchase listener to process
      final waitTime = isTestMode ? 3 : 5;
      await Future.delayed(Duration(seconds: waitTime));

      // Check final status after restore
      final isPremiumNow = await SubscriptionService.isPremium();

      print('🔄 [verifyNow] Status after Play Store check: $isPremiumNow');

      // Always emit the result
      _subscriptionStatusController.add(isPremiumNow);

      if (hadPremium && !isPremiumNow) {
        print('🔥 [verifyNow] ⚠️ REFUND DETECTED! Subscription was cancelled/refunded!');
      }
    } catch (e) {
      print('❌ [verifyNow] Error: $e');
      final localStatus = await SubscriptionService.isPremium();
      _subscriptionStatusController.add(localStatus);
    }
  }

  // ✅ Start background checking
  static void startBackgroundChecking() {
    if (_backgroundTimer != null) return;

    // 🔥 IMPROVED: More frequent checks for faster refund detection
    final checkInterval = isTestMode ? 5 : 15; // Reduced from 10s/30s to 5s/15s
    print('⏰ [SubscriptionService] Starting background checks every $checkInterval seconds (${isTestMode ? "TEST" : "PRODUCTION"} mode)');

    // Check immediately
    _performBackgroundCheck();

    _backgroundTimer = Timer.periodic(Duration(seconds: checkInterval), (_) {
      _performBackgroundCheck();
    });
  }

  // 🔥 COMPLETELY REWRITTEN: Faster refund detection
  static Future<void> _performBackgroundCheck() async {
    _checkCounter++;
    print('🔍 [Background] ═══ Check #$_checkCounter START ═══');

    try {
      // Step 1: Always check local expiry first (this is instant)
      final currentPremiumStatus = await SubscriptionService.isPremium();
      print('🔍 [Background] Local premium status: $currentPremiumStatus');

      // If not premium locally, emit and we're done
      if (!currentPremiumStatus) {
        print('🔍 [Background] Not premium locally - emitting false');
        _subscriptionStatusController.add(false);
        print('🔍 [Background] ═══ Check #$_checkCounter END ═══');
        return;
      }

      // Step 2: User is premium locally - verify with Play Store
      // 🔥 KEY CHANGE: Check with Play Store MORE FREQUENTLY
      // Test mode: Every check (every 5 seconds)
      // Production: Every 2 checks (every 30 seconds instead of 3 minutes)
      final verifyInterval = isTestMode ? 1 : 2;

      if (_checkCounter % verifyInterval != 0) {
        print('🔍 [Background] Premium but skipping Play Store check until #${(_checkCounter ~/ verifyInterval + 1) * verifyInterval}');
        // Still emit current status to keep listeners updated
        _subscriptionStatusController.add(true);
        print('🔍 [Background] ═══ Check #$_checkCounter END ═══');
        return;
      }

      print('🔍 [Background] ⏰ Time for Play Store verification!');

      final prefs = await SharedPreferences.getInstance();
      final originalIsPremium = prefs.getBool("isPremium") ?? false;

      print('🔍 [Background] Verifying with Play Store...');

      // Verify with Play Store
      final iap = InAppPurchase.instance;
      await iap.restorePurchases();

      // Wait for purchase listener to process
      final waitTime = isTestMode ? 2 : 4; // Reduced wait time
      await Future.delayed(Duration(seconds: waitTime));

      // Check final status after restore
      final finalPremiumStatus = await SubscriptionService.isPremium();

      print('🔍 [Background] Play Store result: $finalPremiumStatus');

      // Emit the current status
      _subscriptionStatusController.add(finalPremiumStatus);

      if (originalIsPremium && !finalPremiumStatus) {
        print('🔥 [Background] ⚠️⚠️⚠️ REFUND DETECTED! Subscription cancelled/refunded! ⚠️⚠️⚠️');
      } else if (originalIsPremium == finalPremiumStatus) {
        print('🔍 [Background] ✅ Status unchanged: $finalPremiumStatus');
      } else {
        print('🔍 [Background] Status changed: $originalIsPremium → $finalPremiumStatus');
      }

      print('🔍 [Background] ═══ Check #$_checkCounter END ═══');
    } catch (e) {
      print('❌ [Background] Error in check #$_checkCounter: $e');
      print('🔍 [Background] ═══ Check #$_checkCounter END (ERROR) ═══');
    }
  }

  // ✅ Stop background checking
  static void stopBackgroundChecking() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  Future<PurchaseStatus?> buyMonthly() async {
    if (monthlyProduct == null) return null;

    try {
      final completer = Completer<PurchaseStatus>();
      _purchaseCompleter['monthly'] = completer;

      final purchaseParam = PurchaseParam(productDetails: monthlyProduct!);
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);

      final status = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => PurchaseStatus.canceled,
      );

      return status;
    } catch (e) {
      print('Purchase error: $e');
      return PurchaseStatus.error;
    } finally {
      _purchaseCompleter.remove('monthly');
    }
  }

  Future<void> _listenToPurchase(List<PurchaseDetails> purchases) async {
    print('📦 [_listenToPurchase] Received ${purchases.length} purchase(s)');

    for (final purchase in purchases) {
      print('📦 [_listenToPurchase] Processing: ${purchase.productID}, status: ${purchase.status}');

      if (purchase.productID == "monthly") {
        if (_purchaseCompleter.containsKey('monthly')) {
          _purchaseCompleter['monthly']!.complete(purchase.status);
        }

        if (purchase.status == PurchaseStatus.purchased) {
          print('📦 Purchase status: PURCHASED');
          await _handleActivePurchase(purchase);

          // ✅ Notify all screens about subscription change
          _subscriptionStatusController.add(true);

          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
        } else if (purchase.status == PurchaseStatus.restored) {
          print('📦 Purchase status: RESTORED');
          await _handleActivePurchase(purchase);

          // ✅ Notify all screens
          _subscriptionStatusController.add(true);

          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
        } else if (purchase.status == PurchaseStatus.error ||
            purchase.status == PurchaseStatus.canceled) {
          print('📦 Purchase status: ERROR or CANCELED');
          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
        }
      }
    }
  }

  Future<void> _handleActivePurchase(PurchaseDetails purchase) async {
    try {
      DateTime expiryDate;

      // ✅ Test mode: 5 minutes | Production: 30 days
      final subscriptionDuration = isTestMode
          ? const Duration(minutes: 5)
          : const Duration(days: 30);

      print('📦 [_handleActivePurchase] Using duration: ${isTestMode ? "5 minutes (TEST)" : "30 days (PRODUCTION)"}');

      if (purchase.transactionDate != null) {
        final transactionDate = DateTime.fromMillisecondsSinceEpoch(
            int.parse(purchase.transactionDate!)
        );
        expiryDate = transactionDate.add(subscriptionDuration);
        print('📦 [_handleActivePurchase] Transaction date: $transactionDate');
      } else {
        expiryDate = DateTime.now().add(subscriptionDuration);
        print('📦 [_handleActivePurchase] No transaction date, using current time');
      }

      print('📦 [_handleActivePurchase] Setting expiry to: $expiryDate');
      await _setPremiumWithExpiry(true, expiryDate);

      print('✅ [_handleActivePurchase] Subscription active until: $expiryDate');
    } catch (e) {
      print('❌ [_handleActivePurchase] Error: $e');
      // Fallback with correct duration
      final subscriptionDuration = isTestMode
          ? const Duration(minutes: 5)
          : const Duration(days: 30);
      final expiryDate = DateTime.now().add(subscriptionDuration);
      await _setPremiumWithExpiry(true, expiryDate);
      print('⚠️ [_handleActivePurchase] Used fallback expiry: $expiryDate');
    }
  }

  Future<bool> restorePurchases() async {
    try {
      print('🔄 [restorePurchases] Starting restore process...');

      final prefs = await SharedPreferences.getInstance();
      final hadPremium = prefs.getBool("isPremium") ?? false;
      print('🔄 Current local premium status: $hadPremium');

      await prefs.remove("isPremium");
      await prefs.remove("subscriptionExpiry");
      print('🔄 Local data cleared');

      await _iap.restorePurchases();
      await Future.delayed(const Duration(seconds: 3));

      final isPremiumAfterRestore = prefs.getBool("isPremium") ?? false;
      print('🔄 After restore - isPremium: $isPremiumAfterRestore');

      if (!isPremiumAfterRestore) {
        print('⚠️ No active subscription found in Google Play');
        _subscriptionStatusController.add(false);
        return false;
      }

      final isStillValid = await SubscriptionService.isPremium();
      print('🔄 Expiry verification result: $isStillValid');

      _subscriptionStatusController.add(isStillValid);

      if (!isStillValid) {
        print('⚠️ Subscription found but expired');
        return false;
      }

      print('✅ Active subscription verified');
      return true;
    } catch (e) {
      print('❌ [restorePurchases] Error: $e');
      rethrow;
    }
  }

  Future<void> _setPremiumWithExpiry(bool value, DateTime expiryDate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("isPremium", value);
    await prefs.setString("subscriptionExpiry", expiryDate.toIso8601String());
  }

  // 🔥 CRITICAL METHOD: This detects expiry by checking the date
  static Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    final isPremium = prefs.getBool("isPremium") ?? false;

    if (!isPremium) {
      return false;
    }

    final expiryString = prefs.getString("subscriptionExpiry");

    if (expiryString == null) {
      await prefs.remove("isPremium");
      _subscriptionStatusController.add(false);
      return false;
    }

    try {
      final expiryDate = DateTime.parse(expiryString);
      final now = DateTime.now();

      if (now.isAfter(expiryDate)) {
        print('⚠️ [isPremium] SUBSCRIPTION EXPIRED!');
        print('⚠️ [isPremium] Expiry: $expiryDate, Now: $now');
        await prefs.setBool("isPremium", false);
        await prefs.remove("subscriptionExpiry");

        // ✅ Notify all screens about expiry
        _subscriptionStatusController.add(false);

        return false;
      }

      return true;
    } catch (e) {
      print('❌ [isPremium] Error: $e');
      await prefs.remove("isPremium");
      await prefs.remove("subscriptionExpiry");
      _subscriptionStatusController.add(false);
      return false;
    }
  }

  static Future<int?> getRemainingDays() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryString = prefs.getString("subscriptionExpiry");

    if (expiryString == null) return null;

    try {
      final expiryDate = DateTime.parse(expiryString);
      final now = DateTime.now();

      if (now.isAfter(expiryDate)) return 0;

      return expiryDate.difference(now).inDays;
    } catch (e) {
      return null;
    }
  }

  static Future<void> setTestExpiry(DateTime expiryDate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("isPremium", true);
    await prefs.setString("subscriptionExpiry", expiryDate.toIso8601String());
    print('⏰ Test expiry set to: $expiryDate');
  }

  static Future<String?> getExpiryDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("subscriptionExpiry");
  }

  Future<bool> verifySubscriptionStatus() async {
    try {
      print('🔍 [verifySubscriptionStatus] Checking with Google Play...');

      final prefs = await SharedPreferences.getInstance();
      final hadPremium = prefs.getBool("isPremium") ?? false;

      await prefs.remove("isPremium");
      await prefs.remove("subscriptionExpiry");

      await _iap.restorePurchases();
      await Future.delayed(const Duration(seconds: 3));

      final isPremiumAfterCheck = prefs.getBool("isPremium") ?? false;

      if (hadPremium && !isPremiumAfterCheck) {
        print('⚠️ SUBSCRIPTION WAS CANCELLED/EXPIRED!');
      }

      final isValid = await SubscriptionService.isPremium();

      // ✅ Notify all screens
      _subscriptionStatusController.add(isValid);

      print('🔍 Final result: $isValid');
      return isValid;
    } catch (e) {
      print('❌ [verifySubscriptionStatus] Error: $e');
      return false;
    }
  }

  static Future<void> clearSubscriptionData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("isPremium");
    await prefs.remove("subscriptionExpiry");

    // ✅ Notify all screens
    _subscriptionStatusController.add(false);

    print('🗑️ All subscription data cleared');
  }

  void dispose() {
    _subscription?.cancel();
    _purchaseCompleter.clear();
  }

  static void disposeStatic() {
    stopBackgroundChecking();
    _subscriptionStatusController.close();
  }
}