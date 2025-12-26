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

    // ✅ Start background checking when service initializes
    startBackgroundChecking();
  }

  // ✅ Start background checking
  static void startBackgroundChecking() {
    if (_backgroundTimer != null) return;

    final checkInterval = isTestMode ? 10 : 30;
    print('⏰ [SubscriptionService] Starting background checks every $checkInterval seconds (${isTestMode ? "TEST" : "PRODUCTION"} mode)');

    // Check immediately
    _performBackgroundCheck();

    _backgroundTimer = Timer.periodic(Duration(seconds: checkInterval), (_) {
      _performBackgroundCheck();
    });
  }

  // 🔥 FIXED: This is the critical method that was causing the issue
  static Future<void> _performBackgroundCheck() async {
    _checkCounter++;
    print('🔍 [Background] ═══ Check #$_checkCounter START ═══');

    try {
      // ✅ CRITICAL FIX: Always check isPremium() which validates expiry date
      final currentPremiumStatus = await SubscriptionService.isPremium();
      print('🔍 [Background] Current premium status: $currentPremiumStatus');

      // ✅ ALWAYS emit the current status to ensure listeners are in sync
      // This fixes the case where expiry is detected but stream isn't emitted
      print('🔍 [Background] 📡 Emitting status to stream: $currentPremiumStatus');
      _subscriptionStatusController.add(currentPremiumStatus);

      // If not premium, we're done - no need to verify with Play Store
      if (!currentPremiumStatus) {
        print('🔍 [Background] Not premium - skipping Play Store verification');
        print('🔍 [Background] ═══ Check #$_checkCounter END ═══');
        return;
      }

      // ✅ If premium, verify with Play Store periodically
      // Test mode: Every 3 checks = 30 seconds
      // Production: Every 6 checks = 3 minutes
      final verifyInterval = isTestMode ? 3 : 6;

      if (_checkCounter % verifyInterval != 0) {
        print('🔍 [Background] Premium but skipping Play Store check (will verify at #${(_checkCounter ~/ verifyInterval + 1) * verifyInterval})');
        print('🔍 [Background] ═══ Check #$_checkCounter END ═══');
        return;
      }

      print('🔍 [Background] ⏰ Time for Play Store verification!');

      // Verify with Play Store
      final prefs = await SharedPreferences.getInstance();
      final originalIsPremium = prefs.getBool("isPremium") ?? false;
      final originalExpiry = prefs.getString("subscriptionExpiry");

      print('🔍 [Background] Before restore: isPremium=$originalIsPremium, expiry=$originalExpiry');

      // Call restore to check with Play Store
      final iap = InAppPurchase.instance;
      await iap.restorePurchases();

      // Wait for purchase listener to process
      final waitTime = isTestMode ? 3 : 5;
      await Future.delayed(Duration(seconds: waitTime));

      // Check final status after restore
      final finalPremiumStatus = await SubscriptionService.isPremium();
      final afterExpiry = prefs.getString("subscriptionExpiry");

      print('🔍 [Background] After restore: isPremium=$finalPremiumStatus, expiry=$afterExpiry');

      // ✅ CRITICAL: Emit the final status regardless of what it is
      if (originalIsPremium != finalPremiumStatus) {
        print('🔍 [Background] ⚠️ STATUS CHANGED: $originalIsPremium → $finalPremiumStatus');
        print('🔍 [Background] 📡 Emitting changed status: $finalPremiumStatus');
        _subscriptionStatusController.add(finalPremiumStatus);
      } else {
        print('🔍 [Background] ✅ Status unchanged: $finalPremiumStatus');
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

  // 🔥 FIXED: Use correct duration based on test mode
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