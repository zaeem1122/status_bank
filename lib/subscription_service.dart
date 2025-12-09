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

        await _setPremium(true);
        InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  Future<void> _setPremium(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("isPremium", value);
  }

  static Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool("isPremium") ?? false;
  }
}
