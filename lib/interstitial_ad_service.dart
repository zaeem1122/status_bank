import 'package:google_mobile_ads/google_mobile_ads.dart';

class InterstitialService {
  static InterstitialAd? _interstitialAd;

  static void loadAd() {
    InterstitialAd.load(
      adUnitId: "ca-app-pub-5697489208417002/2502278282",
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          print("Interstitial Loaded");
        },
        onAdFailedToLoad: (error) {
          print("Interstitial Failed: $error");
          _interstitialAd = null;
        },
      ),
    );
  }

  static void show() {
    if (_interstitialAd == null) {
      print("Interstitial not ready — loading...");
      loadAd();
      return;
    }

    _interstitialAd!.fullScreenContentCallback =
        FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            loadAd(); // load next ad
          },
          onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            loadAd();
          },
        );

    _interstitialAd!.show();
    _interstitialAd = null;
  }
}
