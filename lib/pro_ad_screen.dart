import 'package:flutter/material.dart';
import 'package:status_bank/widget.dart';
import 'package:status_bank/subscription_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  final _subService = SubscriptionService();
  bool isLoading = false;
  bool isPremium = false;
  String? subscriptionPrice;
  StreamSubscription<bool>? _subscriptionListener;

  @override
  void initState() {
    super.initState();

    print('⚡ [ProScreen] Screen opened');

    // Check initial premium status
    _checkPremiumStatus();

    // Initialize subscription service
    _initializeSubscription();

    // ✅ Listen to subscription changes from SubscriptionService
    // This ensures UI updates immediately when subscription changes
    // (including when cancelled from Play Console while app was closed)
    _subscriptionListener = SubscriptionService.subscriptionStatusStream.listen(
          (premium) {
        print('🔔 [ProScreen] Subscription status changed: $premium');
        if (mounted && isPremium != premium) {
          setState(() {
            isPremium = premium;
          });
          print('✅ [ProScreen] UI updated to reflect new status');
        }
      },
    );
  }

  @override
  void dispose() {
    print('👋 [ProScreen] Screen closing');
    _subscriptionListener?.cancel();
    _subService.dispose();
    super.dispose();
  }

  Future<void> _initializeSubscription() async {
    await _subService.init();
    if (mounted) {
      setState(() {
        subscriptionPrice = _subService.monthlyProduct?.price;
      });
    }
  }

  Future<void> _checkPremiumStatus() async {
    print('🔄 [ProScreen] Checking premium status...');
    final premium = await SubscriptionService.isPremium();
    print('🔄 [ProScreen] Premium status: $premium');

    if (mounted && premium != isPremium) {
      print('🔄 [ProScreen] Status changed: $isPremium → $premium');
      setState(() {
        isPremium = premium;
      });
    }
  }

  Future<void> subscribe() async {
    if (isLoading || isPremium) return;

    setState(() => isLoading = true);

    try {
      final status = await _subService.buyMonthly();

      if (!mounted) return;

      setState(() => isLoading = false);

      if (status == PurchaseStatus.purchased) {
        // ✅ No need to manually check - subscription stream will update automatically
        showCustomOverlay(context, "Subscription activated successfully!");
      } else if (status == PurchaseStatus.pending) {
        showCustomOverlay(context, "Purchase pending. Please check back later.");
      } else if (status == PurchaseStatus.canceled) {
        // User cancelled - no message needed
      } else if (status == PurchaseStatus.error) {
        showCustomOverlay(context, "Purchase failed. Please try again.");
      }
    } catch (e) {
      print('❌ [ProScreen] Purchase error: $e');
      if (mounted) {
        setState(() => isLoading = false);
        showCustomOverlay(context, "Something went wrong. Please try again.");
      }
    }
  }

  Future<void> restorePurchases() async {
    if (isLoading) return;

    setState(() => isLoading = true);

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checking with Google Play Store...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final wasPremium = isPremium;
      final restored = await _subService.restorePurchases();

      if (!mounted) return;

      setState(() => isLoading = false);

      // ✅ Wait a moment for the subscription stream to update
      await Future.delayed(const Duration(milliseconds: 500));

      if (restored && isPremium) {
        showCustomOverlay(context, "Subscription restored successfully!");
      } else if (wasPremium && !isPremium) {
        showCustomOverlay(
          context,
          "Subscription cancelled or expired. No active subscription found in Google Play Store.",
        );
      } else {
        showCustomOverlay(
          context,
          "No active subscription found. Please subscribe to continue.",
        );
      }
    } catch (e) {
      print('❌ [ProScreen] Restore error: $e');
      if (mounted) {
        setState(() => isLoading = false);
        showCustomOverlay(
          context,
          "Failed to check subscription status. Please try again.",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: Colors.white),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal, Color(0xFF05615B)],
              begin: Alignment.centerLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 45.0, bottom: 20.0),
              child: Text(
                isPremium ? "VIP Member" : "VIP Subscription",
                style: const TextStyle(
                  color: Colors.teal,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // ✅ Shows "Active" badge when subscribed
            // Will disappear automatically via subscription stream when cancelled
            if (isPremium)
              Container(
                margin: const EdgeInsets.only(bottom: 40),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, color: Colors.green, size: 24),
                    SizedBox(width: 8),
                    Text(
                      "Active Subscription",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 40),

            buildFeature("Status Saver"),
            buildFeature("Remove Ads"),
            buildFeature("Direct Chat"),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: subscriptionPrice != null
                  ? Text(
                "$subscriptionPrice/Month to Remove Ads",
                style: const TextStyle(fontSize: 14),
              )
                  : const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),

            // ✅ Button updates automatically via subscription stream
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 15),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPremium ? Colors.green : Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: isPremium ? null : (isLoading ? null : subscribe),
                  child: isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : Text(
                    isPremium ? "SUBSCRIBED ✓" : "BUY NOW",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            TextButton(
              onPressed: isLoading ? null : restorePurchases,
              child: Text(
                "Restore Purchases",
                style: TextStyle(
                  color: isLoading ? Colors.grey : Colors.teal,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),

            const SizedBox(height: 2),

            const Text(
              "You can cancel auto subscription\nanytime from Google Play Store",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),

            const SizedBox(height: 70),
          ],
        ),
      ),
    );
  }

  Widget buildFeature(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Icon(Icons.check, color: Colors.teal, size: 30),
        ],
      ),
    );
  }
}