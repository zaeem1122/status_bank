import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:status_bank/widget.dart';
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
      showCustomOverlay(context, "Enter the Phone Number");
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
      showCustomOverlay(context, "WhatsApp is not installed");
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 600;
    final isLargeScreen = screenWidth >= 600;

    // Responsive sizing
    final iconSize = isSmallScreen ? 100.0 : (isMediumScreen ? 130.0 : 150.0);
    final fontSize = isSmallScreen ? 13.0 : 15.0;
    final labelFontSize = isSmallScreen ? 12.0 : 14.0;
    final buttonFontSize = isSmallScreen ? 13.0 : 15.0;
    final horizontalPadding = isSmallScreen ? 12.0 : 16.0;
    final verticalSpacing = isSmallScreen ? 8.0 : 10.0;
    final borderWidth = isSmallScreen ? 2.0 : 3.0;
    final dropdownPadding = isSmallScreen ? 6.0 : 8.0;
    final buttonVerticalPadding = isSmallScreen ? 8.0 : 10.0;

    // Calculate max width for large screens (tablets)
    final contentMaxWidth = isLargeScreen ? 500.0 : double.infinity;

    return Scaffold(
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: Padding(
          padding: EdgeInsets.only(left: isSmallScreen ? 4.0 : 8.0),
          child: Text(
            "Direct Chat",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isSmallScreen ? 18.0 : 20.0,
            ),
          ),
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(height: screenHeight * 0.02),
                  Icon(
                    Icons.person,
                    size: iconSize,
                    color: Colors.teal,
                  ),
                  SizedBox(height: verticalSpacing),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: dropdownPadding,
                            vertical: isSmallScreen ? 2 : 3,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.teal, width: borderWidth),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedCode,
                              items: countries.map((code) {
                                return DropdownMenuItem<String>(
                                  value: code,
                                  child: Text(
                                    code,
                                    style: TextStyle(fontSize: fontSize),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  selectedCode = value!;
                                });
                              },
                            ),
                          ),
                        ),
                        SizedBox(width: verticalSpacing),
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(fontSize: fontSize),
                            decoration: InputDecoration(
                              label: Text("Phone Number"),
                              labelStyle: TextStyle(
                                color: Colors.teal,
                                fontSize: labelFontSize,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen ? 10 : 12,
                                vertical: isSmallScreen ? 12 : 14,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(10)),
                                borderSide: BorderSide(width: 2, color: Colors.teal),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(10)),
                                borderSide: BorderSide(width: borderWidth, color: Colors.teal),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: verticalSpacing),
                  Padding(
                    padding: EdgeInsets.all(horizontalPadding),
                    child: TextField(
                      controller: _messageController,
                      maxLines: 3,
                      style: TextStyle(fontSize: fontSize),
                      decoration: InputDecoration(
                        labelText: "Message",
                        labelStyle: TextStyle(
                          color: Colors.teal,
                          fontSize: labelFontSize,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 10 : 12,
                          vertical: isSmallScreen ? 10 : 12,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          borderSide: BorderSide(width: borderWidth, color: Colors.teal),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          borderSide: BorderSide(width: borderWidth, color: Colors.teal),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 15 : 20),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _openWhatsapp(isBusiness: false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: EdgeInsets.symmetric(vertical: buttonVerticalPadding),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              "Whatsapp",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: buttonFontSize,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: isSmallScreen ? 12 : 20),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _openWhatsapp(isBusiness: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: EdgeInsets.symmetric(vertical: buttonVerticalPadding),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              "B.Whatsapp",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: buttonFontSize,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}