// setting_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_bank/pro_ad_screen.dart';
import 'package:status_bank/widget.dart' show showCustomOverlay;

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

  Future<void> _saveAutoSave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enabled_auto_save', value);
    setState(() => autoSave = value);

    if (value) {
      await widget.onAutoSaveEnabled();
      showCustomOverlay(context, "Auto-Save Enabled");
    } else {
      showCustomOverlay(context, "Auto-Save Disabled");
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
              onChanged: _saveAutoSave,
              contentPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 16),
            ),
            const Divider(),
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
            ),
            const Divider(),
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
            ),
            const Divider(),
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
            ),
            const Divider(),
            ListTile(
              title: Text(
                "Version",
                style: TextStyle(fontSize: titleFontSize),
              ),
              subtitle: Text(
                "Version 2.11.1.10",
                style: TextStyle(fontSize: subtitleFontSize),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 16),
            ),
          ],
        ),
      ),
    );
  }
}