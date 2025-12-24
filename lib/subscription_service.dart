import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class SubscriptionService {
  final InAppPurchase _iap = InAppPurchase.instance;
  ProductDetails? monthlyProduct;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Track purchase completion status
  final _purchaseCompleter = <String, Completer<PurchaseStatus>>{};

  // ✅ NEW: Global stream to notify all screens about subscription changes
  static final _subscriptionStatusController = StreamController<bool>.broadcast();
  static Stream<bool> get subscriptionStatusStream => _subscriptionStatusController.stream;

  // ✅ NEW: Background timer for periodic checks (10 seconds for testing, 30 for production)
  static Timer? _backgroundTimer;
  static int _checkCounter = 0; // ✅ Track how many checks we've done

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

  // ✅ NEW: Start background checking (10 seconds in test mode, 30 seconds in production)
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

  static Future<void> _performBackgroundCheck() async {
    _checkCounter++;
    print('🔍 [Background] Check #$_checkCounter - Checking subscription status...');

    // First check local status
    final localPremium = await SubscriptionService.isPremium();
    print('🔍 [Background] Local status: $localPremium');

    // ✅ If not premium, just notify once and return
    if (!localPremium) {
      _subscriptionStatusController.add(false);
      return;
    }

    // ✅ Only do Play Store verification periodically:
    // Test mode (5-min subscriptions): Every 3 checks = 30 seconds
    // Production mode (30-day subscriptions): Every 6 checks = 3 minutes
    final verifyInterval = isTestMode ? 3 : 6;

    if (_checkCounter % verifyInterval != 0) {
      print('🔍 [Background] Skipping Play Store check (will check at #${(_checkCounter ~/ verifyInterval + 1) * verifyInterval})');
      return;
    }

    print('🔍 [Background] ⏰ Time for Play Store verification!');

    // ✅ Verify with Play Store by clearing and restoring
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save original data to restore if verification fails
      final originalIsPremium = prefs.getBool("isPremium") ?? false;
      final originalExpiry = prefs.getString("subscriptionExpiry");
      print('🔍 [Background] Original: isPremium=$originalIsPremium, expiry=$originalExpiry');

      // Don't clear data, just try to restore
      // If there's an active subscription, it will update the data
      // If there's no subscription, the data won't be updated

      print('🔍 [Background] Calling restorePurchases...');

      // Check with Play Store
      final iap = InAppPurchase.instance;
      await iap.restorePurchases();

      // Wait for purchase listener to process
      // Test mode: 3 seconds (faster detection)
      // Production: 5 seconds (more reliable for 30-day subs)
      final waitTime = isTestMode ? 3 : 5;
      await Future.delayed(Duration(seconds: waitTime));

      // Check result
      final afterIsPremium = prefs.getBool("isPremium") ?? false;
      final afterExpiry = prefs.getString("subscriptionExpiry");

      print('🔍 [Background] After restore: isPremium=$afterIsPremium, expiry=$afterExpiry');

      // ✅ Only notify if there was a premium status and now there isn't
      // This prevents false positives from slow network/restore
      if (originalIsPremium && !afterIsPremium) {
        // Double-check by verifying expiry date
        final isStillValid = await SubscriptionService.isPremium();
        if (!isStillValid) {
          print('🔍 [Background] ⚠️ SUBSCRIPTION EXPIRED! Notifying listeners...');
          _subscriptionStatusController.add(false);
        } else {
          print('🔍 [Background] ✅ Subscription still valid via expiry check');
        }
      } else if (afterIsPremium) {
        print('🔍 [Background] ✅ Subscription still active');
      } else {
        print('🔍 [Background] ℹ️ Was not premium before, still not premium');
      }
    } catch (e) {
      print('❌ [Background] Error checking with Play Store: $e');
      // On error, don't change anything - keep existing status
    }
  }

  // ✅ NEW: Stop background checking
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

      if (purchase.transactionDate != null) {
        final transactionDate = DateTime.fromMillisecondsSinceEpoch(
            int.parse(purchase.transactionDate!)
        );
        expiryDate = transactionDate.add(const Duration(days: 30));
      } else {
        expiryDate = DateTime.now().add(const Duration(days: 30));
      }

      await _setPremiumWithExpiry(true, expiryDate);
    } catch (e) {
      print('Error handling purchase: $e');
      final expiryDate = DateTime.now().add(const Duration(days: 30));
      await _setPremiumWithExpiry(true, expiryDate);
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
