
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  String selectedCode = "+92"; // default Pakistan
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  // List of countries with codes
  final List<String> countries = [
    "+92",
    "+91",
    "+1",
    "+44",
    "+41",
    "+61",
    "+49",
    "+966",
    "+971",
  ];

  Future<void> _openWhatsapp({required bool isBusiness}) async {
    String phone = _phoneController.text.trim();
    String message = Uri.encodeComponent(_messageController.text.trim());

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Enter the Phone Number")));
      return;
    }

    String fullNumber = selectedCode + phone;
    final String package = isBusiness ? "com.whatsapp.w4b" : "com.whatsapp";

    // We'll use the wa.me link for the AndroidIntent data for better package forcing
    final Uri whatsappWebLink = Uri.parse("https://wa.me/$fullNumber?text=$message");
    // Also keep the direct whatsapp:// URI as an ultimate fallback if all else fails
    final Uri whatsappDirectAppLink = Uri.parse("whatsapp://send?phone=$fullNumber&text=$message");


    try {
      // Attempt 1: Use AndroidIntent with wa.me link and specific package
      // This combination is often the most reliable for forcing a specific WhatsApp app.
      final intent = AndroidIntent(
        action: 'action_view',
        data: whatsappWebLink.toString(), // Use wa.me link
        package: package,
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (e) {
      debugPrint("Attempt 1 (AndroidIntent with web link and package) failed: $e");

      // Attempt 2: Fallback to AndroidIntent with direct whatsapp:// link and specific package
      // Sometimes this works where the first one doesn't, or vice-versa.
      try {
        final intent = AndroidIntent(
          action: 'action_view',
          data: whatsappDirectAppLink.toString(), // Use direct app link
          package: package,
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
      } catch (e2) {
        debugPrint("Attempt 2 (AndroidIntent with direct app link and package) failed: $e2");

        // Attempt 3: Ultimate fallback using url_launcher
        // This will often open in the default WhatsApp if both are installed,
        // or prompt the user to choose, or open in browser if no WhatsApp.
        _launchUrlFallback(whatsappWebLink);
      }
    }
  }

  // Helper function for launching URLs and showing error snackbar
  // This serves as the ultimate fallback if AndroidIntent completely fails.
  Future<void> _launchUrlFallback(Uri url) async {
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("WhatsApp is not installed")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Padding(
          padding: EdgeInsets.only(left: 8.0),
          child: Text("Direct Chat",
              style:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Colors.teal, Color(0xFF05615B)],
                begin: Alignment.centerLeft,
                end: Alignment.bottomRight),
          ),
        ),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const Icon(
            Icons.person,
            size: 130,
            color: Colors.teal,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0, left: 16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.teal, width: 3),
                    borderRadius: BorderRadius.circular(10), // round corner
                  ),
                  child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedCode,
                        items: countries.map((code) {
                          return DropdownMenuItem<String>(
                            value: code,
                            child: Text(code, style: const TextStyle(fontSize: 15)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedCode = value!;
                          });
                        },
                      )),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        label: Text("Phone Number"),
                        labelStyle: TextStyle(color: Colors.teal),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(
                                10)),
                            borderSide:
                            BorderSide(width: 2, color: Colors.teal)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(
                                10)),
                            borderSide:
                            BorderSide(width: 3, color: Colors.teal))),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: "Message",
                  labelStyle: TextStyle(color: Colors.teal),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(width: 3, color: Colors.teal)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(width: 3, color: Colors.teal))),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 15.0, right: 15.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _openWhatsapp(isBusiness: false),
                    child: const Text(
                      "Whatsapp",
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        )),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _openWhatsapp(isBusiness: true),
                    child: const Text(
                      "B.Whatsapp",
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}