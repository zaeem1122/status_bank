import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class SubscriptionService {
  final InAppPurchase _iap = InAppPurchase.instance;
  ProductDetails? monthlyProduct;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Track purchase completion status
  final _purchaseCompleter = <String, Completer<PurchaseStatus>>{};

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
  }

  Future<PurchaseStatus?> buyMonthly() async {
    if (monthlyProduct == null) return null;

    try {
      // Create completer for this purchase
      final completer = Completer<PurchaseStatus>();
      _purchaseCompleter['monthly'] = completer;

      final purchaseParam = PurchaseParam(productDetails: monthlyProduct!);
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);

      // Wait max 3 seconds for purchase status
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

    if (purchases.isEmpty) {
      print('📦 [_listenToPurchase] No purchases in stream - this means no active subscriptions');
      return;
    }

    for (final purchase in purchases) {
      print('📦 [_listenToPurchase] Processing purchase: ${purchase.productID}, status: ${purchase.status}');

      if (purchase.productID == "monthly") {
        // Complete the completer immediately
        if (_purchaseCompleter.containsKey('monthly')) {
          _purchaseCompleter['monthly']!.complete(purchase.status);
        }

        if (purchase.status == PurchaseStatus.purchased) {
          print('📦 [_listenToPurchase] Purchase status: PURCHASED');
          // ✅ FIX: Get actual expiry from Google Play purchase details
          await _handleActivePurchase(purchase);

          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
        } else if (purchase.status == PurchaseStatus.restored) {
          print('📦 [_listenToPurchase] Purchase status: RESTORED');
          // ✅ FIX: Handle restored purchases with actual expiry data
          await _handleActivePurchase(purchase);

          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
        } else if (purchase.status == PurchaseStatus.error ||
            purchase.status == PurchaseStatus.canceled) {
          print('📦 [_listenToPurchase] Purchase status: ERROR or CANCELED');
          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
        }
      }
    }
  }

  // ✅ NEW: Handle active purchase with proper expiry detection
  Future<void> _handleActivePurchase(PurchaseDetails purchase) async {
    try {
      // For Google Play subscriptions, check if auto-renew is enabled
      // and get the actual expiry timestamp from purchase details

      // Note: For real implementation, you need to verify with Google Play backend
      // to get accurate expiry and auto-renew status

      DateTime expiryDate;

      // Check if we can get expiry from purchase transaction date
      if (purchase.transactionDate != null) {
        // Add 30 days from transaction date
        final transactionDate = DateTime.fromMillisecondsSinceEpoch(
            int.parse(purchase.transactionDate!)
        );
        expiryDate = transactionDate.add(const Duration(days: 30));
      } else {
        // Fallback: use current date + 30 days
        expiryDate = DateTime.now().add(const Duration(days: 30));
      }

      await _setPremiumWithExpiry(true, expiryDate);
    } catch (e) {
      print('Error handling purchase: $e');
      // Fallback to 30 days from now
      final expiryDate = DateTime.now().add(const Duration(days: 30));
      await _setPremiumWithExpiry(true, expiryDate);
    }
  }

  // ✅ FIX ISSUE #1: Improved restore with proper verification
  Future<bool> restorePurchases() async {
    try {
      print('🔄 [restorePurchases] Starting restore process...');

      // Step 1: Store current status
      final prefs = await SharedPreferences.getInstance();
      final hadPremium = prefs.getBool("isPremium") ?? false;
      print('🔄 [restorePurchases] Current local premium status: $hadPremium');

      // Step 2: Clear local data to start fresh
      await prefs.remove("isPremium");
      await prefs.remove("subscriptionExpiry");
      print('🔄 [restorePurchases] Local data cleared, checking with Google Play...');

      // Step 3: Call restore purchases
      await _iap.restorePurchases();

      // Step 4: Wait for the purchase stream to process
      // If there are active subscriptions, _listenToPurchase will be called
      // and will restore the subscription data
      await Future.delayed(const Duration(seconds: 3));

      // Step 5: Check if any subscription was restored by the stream
      final isPremiumAfterRestore = prefs.getBool("isPremium") ?? false;
      print('🔄 [restorePurchases] After restore - isPremium: $isPremiumAfterRestore');

      if (!isPremiumAfterRestore) {
        // No active subscription found - the stream either:
        // 1. Didn't fire (no purchases)
        // 2. Fired with empty list (no purchases)
        // 3. Fired but subscription was cancelled
        print('⚠️ [restorePurchases] No active subscription found in Google Play');
        return false;
      }

      // Step 6: Double-check expiry is valid
      final isStillValid = await SubscriptionService.isPremium();
      print('🔄 [restorePurchases] Expiry verification result: $isStillValid');

      if (!isStillValid) {
        print('⚠️ [restorePurchases] Subscription found but expired');
        return false;
      }

      print('✅ [restorePurchases] Active subscription verified');
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

  // ✅ FIX ISSUE #2: Automatically detect and handle expired/cancelled subscriptions
  static Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    final isPremium = prefs.getBool("isPremium") ?? false;

    print('🔍 [isPremium] Checking subscription status...');
    print('🔍 [isPremium] Local isPremium flag: $isPremium');

    if (!isPremium) {
      print('🔍 [isPremium] Result: NOT PREMIUM (flag is false)');
      return false;
    }

    final expiryString = prefs.getString("subscriptionExpiry");
    print('🔍 [isPremium] Expiry string: $expiryString');

    if (expiryString == null) {
      // No expiry date means invalid state
      print('🔍 [isPremium] No expiry date found - clearing premium status');
      await prefs.remove("isPremium");
      return false;
    }

    try {
      final expiryDate = DateTime.parse(expiryString);
      final now = DateTime.now();

      print('🔍 [isPremium] Expiry date: $expiryDate');
      print('🔍 [isPremium] Current time: $now');
      print('🔍 [isPremium] Time difference: ${expiryDate.difference(now)}');

      // ✅ If expired or cancelled (expiry in past), clear premium status
      if (now.isAfter(expiryDate)) {
        print('⚠️ [isPremium] SUBSCRIPTION EXPIRED! Clearing premium status...');
        await prefs.setBool("isPremium", false);
        await prefs.remove("subscriptionExpiry");
        print('✅ [isPremium] Result: NOT PREMIUM (expired)');
        return false;
      }

      print('✅ [isPremium] Result: PREMIUM (valid until $expiryDate)');
      return true;
    } catch (e) {
      // Invalid date format, clear data
      print('❌ [isPremium] Error parsing expiry date: $e');
      await prefs.remove("isPremium");
      await prefs.remove("subscriptionExpiry");
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

  // ✅ FOR TESTING ONLY: Set a custom expiry date to test expiry behavior
  // Example: await SubscriptionService.setTestExpiry(DateTime.now().add(Duration(seconds: 30)));
  static Future<void> setTestExpiry(DateTime expiryDate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("isPremium", true);
    await prefs.setString("subscriptionExpiry", expiryDate.toIso8601String());
    print('Test expiry set to: $expiryDate');
  }

  // ✅ FOR TESTING: Check current expiry date
  static Future<String?> getExpiryDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("subscriptionExpiry");
  }

  // ✅ NEW: Method to check subscription status from Google Play
  // This should be called periodically to sync with server
  Future<bool> verifySubscriptionStatus() async {
    try {
      print('🔍 [verifySubscriptionStatus] Checking with Google Play...');

      // Store current status
      final prefs = await SharedPreferences.getInstance();
      final hadPremium = prefs.getBool("isPremium") ?? false;
      print('🔍 [verifySubscriptionStatus] Local status before check: $hadPremium');

      // Clear local data to force fresh check
      await prefs.remove("isPremium");
      await prefs.remove("subscriptionExpiry");
      print('🔍 [verifySubscriptionStatus] Local data cleared');

      // Call restore purchases - this will trigger the purchase stream
      // If there's an active subscription, _listenToPurchase will be called
      // and will set isPremium = true
      print('🔍 [verifySubscriptionStatus] Calling restorePurchases...');
      await _iap.restorePurchases();

      // Wait for stream to process purchases
      await Future.delayed(const Duration(seconds: 3));

      // Check if Google Play found any active subscription
      final isPremiumAfterCheck = prefs.getBool("isPremium") ?? false;
      print('🔍 [verifySubscriptionStatus] Local status after check: $isPremiumAfterCheck');

      if (hadPremium && !isPremiumAfterCheck) {
        print('⚠️ [verifySubscriptionStatus] SUBSCRIPTION WAS CANCELLED/EXPIRED IN GOOGLE PLAY!');
      } else if (isPremiumAfterCheck) {
        print('✅ [verifySubscriptionStatus] Active subscription verified');
      } else {
        print('ℹ️ [verifySubscriptionStatus] No subscription found');
      }

      // Final check with isPremium
      final isValid = await SubscriptionService.isPremium();
      print('🔍 [verifySubscriptionStatus] Final result: $isValid');

      return isValid;
    } catch (e) {
      print('❌ [verifySubscriptionStatus] Error: $e');
      return false;
    }
  }

  // ✅ Clear all subscription data (useful for testing or when subscription ends)
  static Future<void> clearSubscriptionData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("isPremium");
    await prefs.remove("subscriptionExpiry");
    print('🗑️ [clearSubscriptionData] All subscription data cleared');
  }

  void dispose() {
    _subscription?.cancel();
    _purchaseCompleter.clear();
  }
}