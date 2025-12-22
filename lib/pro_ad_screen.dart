import 'package:flutter/material.dart';
import 'package:status_bank/widget.dart';
import 'subscription_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> with WidgetsBindingObserver {
  final SubscriptionService _subService = SubscriptionService();
  bool isLoading = false;
  bool isPremium = false;
  String? subscriptionPrice;
  Timer? _statusCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSubscription();

    print('⏰ [ProScreen] Starting periodic status check timer (every 10 seconds)');
    // ✅ Check subscription status every 10 seconds
    // This checks both local expiry AND verifies with Google Play
    int checkCount = 0;
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      checkCount++;
      print('⏰ [ProScreen] Timer tick #$checkCount - checking status');

      // Check local status every time
      _checkPremiumStatus();

      // Verify with Google Play every 30 seconds (every 3rd check)
      if (checkCount % 3 == 0) {
        print('🔍 [ProScreen] Verifying with Google Play...');
        _verifySubscriptionWithServer();
      }
    });
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _subService.dispose();
    super.dispose();
  }

  // ✅ FIX ISSUE #2: Check status when app resumes to detect expiry/cancellation
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPremiumStatus();
      // Also verify with Google Play to catch cancellations
      _verifySubscriptionWithServer();
    }
  }

  Future<void> _initializeSubscription() async {
    await _subService.init();
    if (mounted) {
      setState(() {
        subscriptionPrice = _subService.monthlyProduct?.price;
      });
    }
    await _checkPremiumStatus();
  }

  // ✅ FIX ISSUE #2: Check local premium status (handles expiry automatically)
  Future<void> _checkPremiumStatus() async {
    print('🔄 [ProScreen] Checking premium status...');
    final premium = await SubscriptionService.isPremium();
    print('🔄 [ProScreen] Premium status result: $premium');

    if (mounted) {
      setState(() {
        isPremium = premium;
      });
      print('🔄 [ProScreen] UI updated - isPremium is now: $isPremium');
    } else {
      print('⚠️ [ProScreen] Widget not mounted - skipping UI update');
    }
  }

  // ✅ NEW: Verify subscription status with Google Play server
  // This catches cancellations that haven't expired yet
  Future<void> _verifySubscriptionWithServer() async {
    try {
      print('🌐 [ProScreen] Starting server verification...');
      print('🌐 [ProScreen] Current isPremium before check: $isPremium');

      final isValid = await _subService.verifySubscriptionStatus();

      print('🌐 [ProScreen] Server verification result: $isValid');
      print('🌐 [ProScreen] Current isPremium state: $isPremium');

      if (mounted) {
        if (isValid != isPremium) {
          print('🌐 [ProScreen] Status changed! Updating UI from $isPremium to $isValid');
          setState(() {
            isPremium = isValid;
          });
          print('🌐 [ProScreen] UI updated successfully - isPremium is now: $isPremium');
        } else {
          print('🌐 [ProScreen] No change in status, UI remains: $isPremium');
        }
      } else {
        print('⚠️ [ProScreen] Widget not mounted, skipping UI update');
      }
    } catch (e) {
      print('❌ [ProScreen] Error verifying subscription: $e');
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
        await _checkPremiumStatus();
        showCustomOverlay(context, "Subscription activated successfully!");
      } else if (status == PurchaseStatus.pending) {
        showCustomOverlay(context, "Purchase pending. Please check back later.");
      } else if (status == PurchaseStatus.canceled) {
        // User cancelled - no message needed
      } else if (status == PurchaseStatus.error) {
        showCustomOverlay(context, "Purchase failed. Please try again.");
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        showCustomOverlay(context, "Something went wrong. Please try again.");
      }
    }
  }

  // ✅ FIX ISSUE #1: Improved restore with better feedback and verification
  Future<void> restorePurchases() async {
    if (isLoading) return;

    setState(() => isLoading = true);

    try {
      // Show loading feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checking with Google Play Store...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Store the status before restore
      final wasPremium = isPremium;

      // Attempt restore (this now clears local data and checks with Google Play)
      final restored = await _subService.restorePurchases();

      if (!mounted) return;

      // Update UI with restore results
      await _checkPremiumStatus();

      setState(() => isLoading = false);

      // Show appropriate message based on what happened
      if (restored && isPremium) {
        // Active subscription found and restored
        showCustomOverlay(context, "Subscription restored successfully!");
      } else if (wasPremium && !isPremium) {
        // Was premium before, but Google Play says no active subscription
        showCustomOverlay(
          context,
          "Subscription cancelled or expired. No active subscription found in Google Play Store.",
        );
      } else {
        // Never had premium or already cleared
        showCustomOverlay(
          context,
          "No active subscription found. Please subscribe to continue.",
        );
      }
    } catch (e) {
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

            // ✅ FIX ISSUE #2: Shows active badge only when truly subscribed
            // Automatically disappears when subscription expires or is cancelled
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

            // ✅ Show remaining days for active subscribers
            if (isPremium)
              FutureBuilder<int?>(
                future: SubscriptionService.getRemainingDays(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    final days = snapshot.data!;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        days > 0
                            ? "$days days remaining"
                            : "Expires today",
                        style: TextStyle(
                          fontSize: 14,
                          color: days < 3 ? Colors.orange : Colors.grey,
                          fontWeight: days < 3 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

            // ✅ Show price only if not subscribed
            if (!isPremium)
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
                    isPremium ? "SUBSCRIBED ✓" : "START FREE TRIAL",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            // ✅ FIX ISSUE #1: Restore Purchases Button with improved functionality
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

            // ✅ DEBUG ONLY: Clear subscription data button (REMOVE IN PRODUCTION)
            if (isPremium)
              TextButton(
                onPressed: isLoading
                    ? null
                    : () async {
                  await SubscriptionService.clearSubscriptionData();
                  await _checkPremiumStatus();
                  showCustomOverlay(
                    context,
                    "Subscription data cleared",
                  );
                },
                child: Text(
                  "Clear Subscription (Debug Only)",
                  style: TextStyle(
                    color: isLoading ? Colors.grey : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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