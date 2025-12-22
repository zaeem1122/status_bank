// setting_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_bank/pro_ad_screen.dart';
import 'package:status_bank/widget.dart' show showCustomOverlay;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

class SettingPage extends StatefulWidget {
  final bool isDarkTheme;
  final Function(bool) onThemeChanged;
  final Future<void> Function() onAutoSaveEnabled;

  const SettingPage({
    super.key,
    required this.isDarkTheme,
    required this.onThemeChanged,
    required this.onAutoSaveEnabled,
  });

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  bool autoSave = false;
  bool _isProcessing = false; // ✅ Prevent multiple clicks during processing

  // ✅ App constants
  static const String appUrl = 'https://play.google.com/store/apps/details?id=com.appntox.statussavermax';
  static const String appName = 'Status Saver Max';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      autoSave = prefs.getBool('enabled_auto_save') ?? false;
    });
  }

  // ✅ FIXED: Smooth auto-save toggle without lag
  Future<void> _saveAutoSave(bool value) async {
    if (_isProcessing) return; // Prevent multiple toggles

    setState(() {
      _isProcessing = true;
      autoSave = value; // ✅ Update UI immediately for smooth toggle
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enabled_auto_save', value);

      if (value) {
        // Run auto-save in background without blocking UI
        widget.onAutoSaveEnabled().then((_) {
          if (mounted) {
            showCustomOverlay(context, "Auto-Save Enabled");
          }
        });
      } else {
        if (mounted) {
          showCustomOverlay(context, "Auto-Save Disabled");
        }
      }
    } catch (e) {
      print('Error saving auto-save setting: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // ✅ Open Privacy Policy URL
  Future<void> _openPrivacyPolicy() async {
    final Uri url = Uri.parse(appUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          showCustomOverlay(context, "Could not open Privacy Policy");
        }
      }
    } catch (e) {
      print('Error opening privacy policy: $e');
      if (mounted) {
        showCustomOverlay(context, "Error opening link");
      }
    }
  }

  // ✅ Rate the app on Play Store
  Future<void> _rateApp() async {
    final Uri url = Uri.parse(appUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          showCustomOverlay(context, "Could not open Play Store");
        }
      }
    } catch (e) {
      print('Error opening Play Store: $e');
      if (mounted) {
        showCustomOverlay(context, "Error opening Play Store");
      }
    }
  }

  // ✅ Share app with others
  Future<void> _shareApp() async {
    try {
      await Share.share(
        'Check out $appName - Save WhatsApp statuses easily!\n\n$appUrl',
        subject: 'Try $appName',
      );
    } catch (e) {
      print('Error sharing app: $e');
      if (mounted) {
        showCustomOverlay(context, "Error sharing app");
      }
    }
  }

  // ✅ Open app on Play Store (for Version tap)
  Future<void> _openPlayStore() async {
    final Uri url = Uri.parse(appUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          showCustomOverlay(context, "Could not open Play Store");
        }
      }
    } catch (e) {
      print('Error opening Play Store: $e');
      if (mounted) {
        showCustomOverlay(context, "Error opening Play Store");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 600;

    // Responsive font sizes
    final titleFontSize = isSmallScreen ? 13.0 : (isMediumScreen ? 14.0 : 16.0);
    final subtitleFontSize = isSmallScreen ? 11.0 : (isMediumScreen ? 12.0 : 14.0);
    final buttonFontSize = isSmallScreen ? 12.0 : 14.0;
    final iconSize = isSmallScreen ? 24.0 : 28.0;

    // Responsive padding
    final containerPadding = isSmallScreen ? 8.0 : 12.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Settings",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isSmallScreen ? 18.0 : 20.0,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal, Color(0xFF05615B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            Container(
              padding: EdgeInsets.all(containerPadding),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // For very small screens, stack vertically
                  if (constraints.maxWidth < 320) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.diamond, color: Colors.teal, size: iconSize),
                            SizedBox(width: isSmallScreen ? 6 : 8),
                            Expanded(
                              child: Text(
                                "Remove All Ads\nEnjoy Status Saver without Ads",
                                style: TextStyle(fontSize: titleFontSize),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ProScreen()),
                            ),
                            child: Text(
                              "Go PRO",
                              style: TextStyle(color: Colors.white, fontSize: buttonFontSize),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  // Default horizontal layout
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.diamond, color: Colors.teal, size: iconSize),
                            SizedBox(width: isSmallScreen ? 6 : 8),
                            Expanded(
                              child: Text(
                                "Remove All Ads\nEnjoy Status Saver without Ads",
                                style: TextStyle(fontSize: titleFontSize),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          padding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen ? 12 : 16,
                            vertical: isSmallScreen ? 8 : 12,
                          ),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ProScreen()),
                        ),
                        child: Text(
                          "Go PRO",
                          style: TextStyle(color: Colors.white, fontSize: buttonFontSize),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(),
            SwitchListTile(
              title: Text(
                "Dark Theme",
                style: TextStyle(fontSize: titleFontSize),
              ),
              subtitle: Text(
                "Choose dark theme of the app",
                style: TextStyle(fontSize: subtitleFontSize),
              ),
              activeColor: Colors.teal,
              value: widget.isDarkTheme,
              onChanged: widget.onThemeChanged,
              contentPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 16),
            ),
            const Divider(),
            // ✅ FIXED: Smooth auto-save toggle
            SwitchListTile(
              title: Text(
                "Auto Save",
                style: TextStyle(fontSize: titleFontSize),
              ),
              subtitle: Text(
                "Save All Statuses With One Click",
                style: TextStyle(fontSize: subtitleFontSize),
              ),
              activeColor: Colors.teal,
              value: autoSave,
              onChanged: _isProcessing ? null : _saveAutoSave, // ✅ Disable during processing
              contentPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 16),
            ),
            const Divider(),
            // ✅ Privacy Policy - Opens Play Store
            ListTile(
              title: Text(
                "Privacy Policy",
                style: TextStyle(fontSize: titleFontSize),
              ),
              subtitle: Text(
                "Our Terms and Conditions",
                style: TextStyle(fontSize: subtitleFontSize),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 16),
              onTap: _openPrivacyPolicy, // ✅ Added tap handler
              trailing: Icon(Icons.open_in_new, color: Colors.teal, size: 20),
            ),
            const Divider(),
            // ✅ Share With Others - Shares app link
            ListTile(
              title: Text(
                "Share With Others",
                style: TextStyle(fontSize: titleFontSize),
              ),
              subtitle: Text(
                "Share With Friends and Family",
                style: TextStyle(fontSize: subtitleFontSize),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 16),
              onTap: _shareApp, // ✅ Added tap handler
              trailing: Icon(Icons.share, color: Colors.teal, size: 20),
            ),
            const Divider(),
            // ✅ Rate Us - Opens Play Store
            ListTile(
              title: Text(
                "Rate Us",
                style: TextStyle(fontSize: titleFontSize),
              ),
              subtitle: Text(
                "Rate our App",
                style: TextStyle(fontSize: subtitleFontSize),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 16),
              onTap: _rateApp, // ✅ Added tap handler
              trailing: Icon(Icons.star, color: Colors.amber, size: 20),
            ),
            const Divider(),
            // ✅ Version - Opens Play Store
            ListTile(
              title: Text(
                "Version",
                style: TextStyle(fontSize: titleFontSize),
              ),
              subtitle: Text(
                "Version 1.7.6",
                style: TextStyle(fontSize: subtitleFontSize),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 16),
              onTap: _openPlayStore, // ✅ Added tap handler
              trailing: Icon(Icons.info_outline, color: Colors.teal, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}