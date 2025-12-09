import 'package:flutter/material.dart';
import 'subscription_service.dart';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  final SubscriptionService _subService = SubscriptionService();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _subService.init();
  }

  Future<void> subscribe() async {
    setState(() => isLoading = true);
    await _subService.buyMonthly();
    await Future.delayed(Duration(seconds: 2));
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close),
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
            const Padding(
              padding: EdgeInsets.only(top: 45.0, bottom: 60.0),
              child: Text(
                "VIP Subscription",
                style: TextStyle(
                  color: Colors.teal,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            buildFeature("Status Saver"),
            buildFeature("Remove Ads"),
            buildFeature("Direct Chat"),

            const Spacer(),

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
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isLoading ? null : subscribe,
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("START FREE TRIAL"),
                ),
              ),
            ),

            const Text(
              "You can cancel auto subscription\nanytime from Google Play Store",
              textAlign: TextAlign.center,
            ),

            SizedBox(height: 40),
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
