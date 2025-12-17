import 'package:flutter/material.dart';
import 'package:status_bank/widget.dart';
import 'subscription_service.dart';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  final SubscriptionService _subService = SubscriptionService();
  bool isLoading = false;
  bool isPremium = false; // ✅ Track subscription status

  @override
  void initState() {
    super.initState();
    _subService.init();
    _checkPremiumStatus(); // ✅ Check if already subscribed
  }

  // ✅ Check subscription status
  Future<void> _checkPremiumStatus() async {
    final premium = await SubscriptionService.isPremium();
    setState(() {
      isPremium = premium;
    });
  }

  Future<void> subscribe() async {
    setState(() => isLoading = true);
    await _subService.buyMonthly();
    await Future.delayed(Duration(seconds: 2));
    await _checkPremiumStatus(); // ✅ Refresh status after purchase
    setState(() => isLoading = false);
  }

  // ✅ Restore purchases function
  Future<void> restorePurchases() async {
    setState(() => isLoading = true);

    try {
      await _subService.restorePurchases();
      await _checkPremiumStatus(); // ✅ Refresh status after restore

      if (mounted) {
        showCustomOverlay(context,
            isPremium
                ? "Subscription restored successfully!"
                : "No active subscription found"
        );
      }
    } catch (e) {
      if (mounted) {
        showCustomOverlay(context, "Failed to Restore");
      }
    } finally {
      setState(() => isLoading = false);
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
                isPremium ? "VIP Member" : "VIP Subscription", // ✅ Change title if subscribed
                style: TextStyle(
                  color: isPremium ? Colors.teal : Colors.teal,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // ✅ Show subscription status badge if premium
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

            // ✅ Show price only if not subscribed
            if (!isPremium)
              const Text(
                "Rs 280.00/Month to Remove Ads",
                style: TextStyle(fontSize: 14),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 15),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPremium ? Colors.green : Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isPremium ? null : (isLoading ? null : subscribe), // ✅ Disable if already subscribed
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                    isPremium ? "SUBSCRIBED ✓" : "START FREE TRIAL", // ✅ Change button text
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

            // ✅ Restore Purchases Button
            TextButton(
              onPressed: isLoading ? null : restorePurchases,
              child: const Text(
                "Restore Purchases",
                style: TextStyle(
                  color: Colors.teal,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              "You can cancel auto subscription\nanytime from Google Play Store",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),

            const SizedBox(height: 40),
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
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Icon(Icons.check, color: Colors.teal, size: 30),
        ],
      ),
    );
  }
}