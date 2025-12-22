import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionService {
  final InAppPurchase _iap = InAppPurchase.instance;
  ProductDetails? monthlyProduct;

  Future<void> init() async {
    final available = await _iap.isAvailable();
    if (!available) return;

    const ids = {"monthly"};
    ProductDetailsResponse response = await _iap.queryProductDetails(ids);

    if (response.productDetails.isNotEmpty) {
      monthlyProduct = response.productDetails.first;
    }

    _iap.purchaseStream.listen(_listenToPurchase);
  }

  Future<void> buyMonthly() async {
    if (monthlyProduct == null) return;

    final purchaseParam = PurchaseParam(productDetails: monthlyProduct!);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _listenToPurchase(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID == "monthly" &&
          purchase.status == PurchaseStatus.purchased) {

        // ✅ Save with expiry date (30 days from now for monthly subscription)
        final expiryDate = DateTime.now().add(Duration(days: 30));
        await _setPremiumWithExpiry(true, expiryDate);
        InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  // ✅ Restore Purchases Method
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      print('Error restoring purchases: $e');
      throw Exception('Failed to restore purchases');
    }
  }

  // ✅ Save premium status with expiry date
  Future<void> _setPremiumWithExpiry(bool value, DateTime expiryDate) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("isPremium", value);
    prefs.setString("subscriptionExpiry", expiryDate.toIso8601String());
  }

  // ✅ Check if subscription is still valid
  static Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    final isPremium = prefs.getBool("isPremium") ?? false;

    if (!isPremium) return false;

    // ✅ Check if subscription has expired
    final expiryString = prefs.getString("subscriptionExpiry");
    if (expiryString == null) return false;

    final expiryDate = DateTime.parse(expiryString);
    final now = DateTime.now();

    // ✅ If expired, clear premium status
    if (now.isAfter(expiryDate)) {
      await prefs.setBool("isPremium", false);
      await prefs.remove("subscriptionExpiry");
      return false;
    }

    return true;
  }

  // ✅ Get remaining days of subscription
  static Future<int?> getRemainingDays() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryString = prefs.getString("subscriptionExpiry");

    if (expiryString == null) return null;

    final expiryDate = DateTime.parse(expiryString);
    final now = DateTime.now();

    if (now.isAfter(expiryDate)) return 0;

    return expiryDate.difference(now).inDays;
  }
}