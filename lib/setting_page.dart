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
      showCustomOverlay(context, "Auto-Save Enabled",);
    } else {
          showCustomOverlay(context, "Auto-Save Disabled",);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Colors.teal, Color(0xFF05615B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
      ),
      body: ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.diamond, color: Colors.teal, size: 28),
                    SizedBox(width: 8),
                    Text("Remove All Ads\nEnjoy Status Saver without Ads", style: TextStyle(fontSize: 14)),
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProScreen())),
                  child: const Text("Go PRO", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text("Dark Theme"),
            subtitle: const Text("Choose dark theme of the app"),
            activeColor: Colors.teal,
            value: widget.isDarkTheme,
            onChanged: widget.onThemeChanged,
          ),
          const Divider(),
          SwitchListTile(
            title: const Text("Auto Save"),
            subtitle: const Text("Save All Statuses With One Click"),
            activeColor: Colors.teal,
            value: autoSave,
            onChanged: _saveAutoSave,
          ),
          const Divider(),
          ListTile(title: const Text("Privacy Policy"), subtitle: const Text("Our Terms and Conditions")),
          const Divider(),
          ListTile(title: const Text("Share With Others"), subtitle: const Text("Share With Friends and Family")),
          const Divider(),
          ListTile(title: const Text("Rate Us"), subtitle: const Text("Rate our App")),
          const Divider(),
          ListTile(title: const Text("Version"), subtitle: const Text("Version 2.11.1.10")),

        ],
      ),
    );
  }
}
