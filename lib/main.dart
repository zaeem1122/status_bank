import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_bank/saved_page.dart';
import 'package:status_bank/setting_page.dart';
import 'package:status_bank/status_tab_page.dart';
import 'package:status_bank/status_tab_papge2.dart';
import 'package:status_bank/subscription_service.dart';

import 'interstitial_ad_service.dart';

// Platform channel for accessing WhatsApp statuses
const platform = MethodChannel('com.yourapp/status_access');

/// Get the appropriate save directory based on Android version
Future<String> _getSaveDirectory(bool isBusiness) async {
  try {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt >= 29) {
        // Android 10+ (API 29+): Use app-specific directory
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          if (isBusiness) {
            return '${externalDir.path}/StatusSaver/Business';
          } else {
            return '${externalDir.path}/StatusSaver';
          }
        }
      } else {
        // Android 9 and below: Use public directory
        if (isBusiness) {
          return '/storage/emulated/0/StatusSaver/Business';
        } else {
          return '/storage/emulated/0/StatusSaver';
        }
      }
    }

    // Fallback
    final externalDir = await getExternalStorageDirectory();
    if (isBusiness) {
      return '${externalDir!.path}/StatusSaver/Business';
    } else {
      return '${externalDir!.path}/StatusSaver';
    }
  } catch (e) {
    print('Error getting save directory: $e');
    // Final fallback
    final externalDir = await getExternalStorageDirectory();
    return '${externalDir!.path}/StatusSaver';
  }
}

/// Get Android version from platform channel
Future<int> _getAndroidVersion() async {
  try {
    final version = await platform.invokeMethod('getAndroidVersion');
    return version as int;
  } catch (e) {
    print('Error getting Android version: $e');
    return 30; // Default to Android 11
  }
}

/// Save all existing statuses when auto-save is first enabled
Future<void> saveAllExistingStatusesForeground() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // Get saved URIs for both WhatsApp types
    final regularUri = prefs.getString('status_folder_uri');
    final businessUri = prefs.getString('status_folder_uri_business');

    // Process regular WhatsApp statuses
    if (regularUri != null && regularUri.isNotEmpty) {
      await _processAndSaveStatuses(regularUri, false, prefs);
    }

    // Process Business WhatsApp statuses
    if (businessUri != null && businessUri.isNotEmpty) {
      await _processAndSaveStatuses(businessUri, true, prefs);
    }

    print('✅ All existing statuses saved');
  } catch (e) {
    print('❌ saveAllExistingStatusesForeground error: $e');
  }
}

/// Process and save statuses from a given URI
Future<void> _processAndSaveStatuses(
    String folderUri, bool isBusiness, SharedPreferences prefs) async {
  try {
    // Get files from the URI using platform channel
    final List<dynamic> files = await platform.invokeMethod(
      'getFilesFromUri',
      {'uri': folderUri, 'isBusiness': isBusiness ? 'true' : 'false'},
    );

    if (files.isEmpty) {
      print('No files found in ${isBusiness ? "Business" : "Regular"} WhatsApp');
      return;
    }

    // Get the appropriate save directory
    final targetPath = await _getSaveDirectory(isBusiness);
    final targetDir = Directory(targetPath);

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
      print('Created directory: $targetPath');
    }

    int savedCount = 0;
    int latestTimestamp = 0;

    for (var file in files) {
      try {
        final fileMap = Map<String, dynamic>.from(file);
        final fileName = fileMap['name'] as String;
        final fileUri = fileMap['uri'] as String;
        final lastModified = fileMap['lastModified'] as int;

        // Track the latest timestamp
        if (lastModified > latestTimestamp) {
          latestTimestamp = lastModified;
        }

        // Check if file already exists
        final destPath = '${targetDir.path}/$fileName';
        if (await File(destPath).exists()) {
          continue; // Skip if already saved
        }

        // Read file bytes from URI
        final bytes = await platform.invokeMethod('readFileBytes', {'uri': fileUri});
        if (bytes != null) {
          await File(destPath).writeAsBytes(bytes as Uint8List);
          savedCount++;
        }
      } catch (e) {
        print('Error saving individual file: $e');
      }
    }

    // Update last seen timestamp
    final key = 'last_seen_${isBusiness ? "business" : "regular"}';
    await prefs.setInt(key, latestTimestamp);

    print('✅ Saved $savedCount files from ${isBusiness ? "Business" : "Regular"} WhatsApp');
  } catch (e) {
    print('❌ Error in _processAndSaveStatuses: $e');
  }
}

/// Check for new statuses periodically (called every 10 seconds)
Future<void> checkStatusesForeground() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final autoSaveEnabled = prefs.getBool('enabled_auto_save') ?? false;

    if (!autoSaveEnabled) {
      return; // Don't check if auto-save is disabled
    }

    // Get saved URIs
    final regularUri = prefs.getString('status_folder_uri');
    final businessUri = prefs.getString('status_folder_uri_business');

    // Check regular WhatsApp for new statuses
    if (regularUri != null && regularUri.isNotEmpty) {
      await _checkAndSaveNewStatuses(regularUri, false, prefs);
    }

    // Check Business WhatsApp for new statuses
    if (businessUri != null && businessUri.isNotEmpty) {
      await _checkAndSaveNewStatuses(businessUri, true, prefs);
    }
  } catch (e) {
    print('❌ checkStatusesForeground error: $e');
  }
}

/// Check and save new statuses from a specific URI
Future<void> _checkAndSaveNewStatuses(
    String folderUri, bool isBusiness, SharedPreferences prefs) async {
  try {
    // Get current files from URI
    final List<dynamic> files = await platform.invokeMethod(
      'getFilesFromUri',
      {'uri': folderUri, 'isBusiness': isBusiness ? 'true' : 'false'},
    );

    if (files.isEmpty) return;

    // Get the last seen timestamp
    final key = 'last_seen_${isBusiness ? "business" : "regular"}';
    final lastSeen = prefs.getInt(key) ?? 0;

    // Filter new files
    final newFiles = files.where((file) {
      final fileMap = Map<String, dynamic>.from(file);
      final lastModified = fileMap['lastModified'] as int;
      return lastModified > lastSeen;
    }).toList();

    if (newFiles.isEmpty) return;

    // Get save directory
    final targetPath = await _getSaveDirectory(isBusiness);
    final targetDir = Directory(targetPath);

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    int savedCount = 0;
    int latestTimestamp = lastSeen;

    for (var file in newFiles) {
      try {
        final fileMap = Map<String, dynamic>.from(file);
        final fileName = fileMap['name'] as String;
        final fileUri = fileMap['uri'] as String;
        final lastModified = fileMap['lastModified'] as int;

        // Track latest timestamp
        if (lastModified > latestTimestamp) {
          latestTimestamp = lastModified;
        }

        // Check if file already exists
        final destPath = '${targetDir.path}/$fileName';
        if (await File(destPath).exists()) {
          continue;
        }

        // Read and save file
        final bytes = await platform.invokeMethod('readFileBytes', {'uri': fileUri});
        if (bytes != null) {
          await File(destPath).writeAsBytes(bytes as Uint8List);
          savedCount++;
          print('📥 Auto-saved: $fileName');
        }
      } catch (e) {
        print('Error auto-saving file: $e');
      }
    }

    // Update last seen timestamp
    if (latestTimestamp > lastSeen) {
      await prefs.setInt(key, latestTimestamp);
    }

    if (savedCount > 0) {
      print('✅ Auto-saved $savedCount new ${isBusiness ? "Business" : "Regular"} statuses');
    }
  } catch (e) {
    print('❌ Error in _checkAndSaveNewStatuses: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only load ads if user is not premium
  final isPremium = await SubscriptionService.isPremium();
  if (!isPremium) {
    InterstitialService.loadAd();
  }

  MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(
      testDeviceIds: ["09357ABB7CD78370747E779FBA319F0F"],
    ),
  );
  await MobileAds.instance.initialize();

  await Permission.storage.request();
  await Permission.manageExternalStorage.request();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkTheme = false;

  void _toggleTheme(bool value) {
    setState(() {
      _isDarkTheme = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Status Saver',
      debugShowCheckedModeBanner: false,
      themeMode: _isDarkTheme ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData.light()
          .copyWith(appBarTheme: const AppBarTheme(backgroundColor: Colors.teal)),
      darkTheme: ThemeData.dark()
          .copyWith(appBarTheme: const AppBarTheme(backgroundColor: Colors.black)),
      home:
      StatusApp(isDarkTheme: _isDarkTheme, onThemeChanged: _toggleTheme),
    );
  }
}

class StatusApp extends StatefulWidget {
  final bool isDarkTheme;
  final Function(bool) onThemeChanged;
  const StatusApp(
      {super.key, required this.isDarkTheme, required this.onThemeChanged});

  @override
  State<StatusApp> createState() => _StatusAppState();
}

class _StatusAppState extends State<StatusApp> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  Timer? _timer;
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // ✅ Add lifecycle observer
    _checkPremiumStatus();
    // Check for new statuses every 10 seconds
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await checkStatusesForeground();
    });
  }

  // ✅ Monitor app lifecycle to refresh premium status when returning from ProScreen
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground, check premium status
      _checkPremiumStatus();
    }
  }

  Future<void> _checkPremiumStatus() async {
    final isPremium = await SubscriptionService.isPremium();

    // ✅ If premium status changed, update UI and handle ads
    if (_isPremium != isPremium) {
      setState(() {
        _isPremium = isPremium;
      });

      if (_isPremium) {
        // ✅ User became premium - dispose banner ad immediately
        _disposeBannerAd();
        print('🎉 User is now premium - banner ad removed');
      } else if (!_isPremium && !_isBannerAdReady) {
        // User is not premium and ad not loaded - load banner ad
        _loadBannnerAds();
      }
    }
  }

  // ✅ New method to dispose banner ad
  void _disposeBannerAd() {
    if (_bannerAd != null) {
      _bannerAd!.dispose();
      _bannerAd = null;
      setState(() {
        _isBannerAdReady = false;
      });
      print('🗑️ Banner ad disposed');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // ✅ Remove lifecycle observer
    _timer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannnerAds() {
    print("📢 Loading Banner Ad...");
    final String AdUnitId = Platform.isAndroid
        ? "ca-app-pub-3940256099942544/9214589741"
        : "ca-app-pub-3940256099942544/2435281174";
    final BannerAd banner = BannerAd(
        size: AdSize.banner,
        adUnitId: AdUnitId,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            print("✅ Banner Ad Loaded Successfully!");
            setState(() {
              _bannerAd = ad as BannerAd;
              _isBannerAdReady = true;
            });
          },
          onAdFailedToLoad: (ad, error) {
            print("❌ Banner Ad Failed to Load: ${error.message}");
            ad.dispose();
          },
          onAdOpened: (ad) => print("📌 Banner Ad Opened (clicked)."),
          onAdClosed: (ad) => print("📌 Banner Ad Closed."),
        ),
        request: const AdRequest());
    banner.load();
  }

  Widget _build(int index) {
    switch (index) {
      case 0:
        return const StatusTabPage(title: "Whatsapp");
      case 1:
        return const StatusTabPage2(title: "Business Whatsapp");
      case 2:
        return const SavedPage();
      case 3:
        return SettingPage(
          isDarkTheme: widget.isDarkTheme,
          onThemeChanged: widget.onThemeChanged,
          onAutoSaveEnabled: saveAllExistingStatusesForeground,
        );
      default:
        return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
        body: _build(_selectedIndex),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          // Only show banner ad if user is not premium
          if (!_isPremium && _isBannerAdReady && _bannerAd != null)
            Container(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              alignment: Alignment.center,
              child: AdWidget(ad: _bannerAd!),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1F1F1F), const Color(0xFF121212)]
                    : [Colors.teal, const Color(0xFF05615B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: BottomNavigationBar(
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.chat), label: "Whatsapp"),
                BottomNavigationBarItem(
                    icon: Icon(Icons.business), label: "Business"),
                BottomNavigationBarItem(icon: Icon(Icons.save), label: "Saved"),
                BottomNavigationBarItem(
                    icon: Icon(Icons.settings), label: "Settings"),
              ],
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.white70,
              backgroundColor: Colors.transparent,
              currentIndex: _selectedIndex,
              onTap: (index) => setState(() => _selectedIndex = index),
            ),
          ),
        ]));
  }
}