import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:status_bank/subscription_service.dart';

/// Global Ads Controller - Manages ads across entire app
/// Automatically loads/removes ads based on subscription status
class AdsController {
  // Singleton instance
  static final AdsController instance = AdsController._internal();
  AdsController._internal();

  // Ad instances
  BannerAd? bannerAd;
  bool isBannerLoaded = false;

  // ✅ ValueNotifier to trigger UI rebuilds when banner status changes
  final ValueNotifier<bool> bannerStatusNotifier = ValueNotifier<bool>(false);

  // Subscription listener
  StreamSubscription<bool>? _subscriptionListener;

  // Track initialization
  bool _isInitialized = false;

  /// Initialize the controller - call this ONCE in main()
  Future<void> init() async {
    if (_isInitialized) {
      print('🎯 [AdsController] Already initialized, skipping');
      return;
    }
    _isInitialized = true;

    print('🎯 [AdsController] Initializing...');

    // Check current premium status
    final isPremium = await SubscriptionService.isPremium();
    print('🎯 [AdsController] Initial premium status: $isPremium');

    if (!isPremium) {
      loadBannerAd();
    }

    // Listen to subscription changes from SubscriptionService
    _subscriptionListener = SubscriptionService.subscriptionStatusStream.listen(
          (isPremium) {
        print('🎯 [AdsController] 🔔 Subscription status changed: isPremium=$isPremium');

        if (isPremium) {
          // User became premium - remove ads immediately
          print('🎯 [AdsController] User is premium → Removing ads');
          removeAds();
        } else {
          // User lost premium - show ads immediately
          print('🎯 [AdsController] User is NOT premium → Loading ads');
          loadBannerAd();
        }
      },
      onError: (error) {
        print('❌ [AdsController] Error in subscription stream: $error');
      },
    );

    print('🎯 [AdsController] ✅ Initialization complete');
  }

  /// Load banner ad
  void loadBannerAd() {
    if (isBannerLoaded) {
      print('🎯 [AdsController] Banner already loaded, skipping');
      return;
    }

    print('🎯 [AdsController] 📢 Loading banner ad...');

    final String adUnitId = Platform.isAndroid
        ? "ca-app-pub-5697489208417002/9726020583"
        : "ca-app-pub-3940256099942544/2435281174";

    bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: adUnitId,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          print('✅ [AdsController] Banner Ad Loaded Successfully!');
          isBannerLoaded = true;
          // ✅ Notify UI to rebuild
          bannerStatusNotifier.value = true;
        },
        onAdFailedToLoad: (ad, error) {
          print('❌ [AdsController] Banner Ad Failed: ${error.message}');
          ad.dispose();
          bannerAd = null;
          isBannerLoaded = false;
          bannerStatusNotifier.value = false;

          // Retry after 5 seconds
          Future.delayed(const Duration(seconds: 5), () {
            if (!isBannerLoaded && bannerAd == null) {
              print('🔄 [AdsController] Retrying banner ad load...');
              loadBannerAd();
            }
          });
        },
        onAdOpened: (ad) => print('📌 [AdsController] Banner Ad Opened'),
        onAdClosed: (ad) => print('📌 [AdsController] Banner Ad Closed'),
      ),
      request: const AdRequest(),
    );

    bannerAd!.load();
  }

  /// Remove all ads
  void removeAds() {
    print('🚫 [AdsController] Removing ads...');

    if (bannerAd != null) {
      bannerAd!.dispose();
      bannerAd = null;
      isBannerLoaded = false;
      // ✅ Notify UI to rebuild
      bannerStatusNotifier.value = false;
      print('✅ [AdsController] Banner ad disposed successfully');
    } else {
      print('ℹ️ [AdsController] No banner ad to remove');
    }
  }

  /// Check if banner is ready to display
  bool get hasBanner => bannerAd != null && isBannerLoaded;

  /// Dispose controller
  void dispose() {
    print('🗑️ [AdsController] Disposing...');
    _subscriptionListener?.cancel();
    _subscriptionListener = null;
    removeAds();
    bannerStatusNotifier.dispose();
    _isInitialized = false;
    print('✅ [AdsController] Disposed successfully');
  }
}