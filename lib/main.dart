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
import 'package:status_bank/ads_controller.dart'; // 🔥 NEW IMPORT

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

/// ✅ Save all existing statuses when auto-save is first enabled (NON-BLOCKING)
Future<void> saveAllExistingStatusesForeground() async {
  // Run in separate isolate/async to avoid blocking UI
  Future.microtask(() async {
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
  });
}

/// Process and save statuses from a given URI - NOW SAVES TO GALLERY
Future<void> _processAndSaveStatuses(
    String folderUri,
    bool isBusiness,
    SharedPreferences prefs,
    ) async {
  try {
    // Get files from the URI using platform channel
    final List<dynamic> files = await platform.invokeMethod('getFilesFromUri', {
      'uri': folderUri,
      'isBusiness': isBusiness ? 'true' : 'false',
    });

    if (files.isEmpty) {
      print(
        'No files found in ${isBusiness ? "Business" : "Regular"} WhatsApp',
      );
      return;
    }

    int savedCount = 0;
    int alreadyExistCount = 0;
    int latestTimestamp = 0;

    // ✅ Process files in smaller batches to avoid blocking
    const batchSize = 5;
    for (int i = 0; i < files.length; i += batchSize) {
      final batch = files.skip(i).take(batchSize);

      for (var file in batch) {
        try {
          final fileMap = Map<String, dynamic>.from(file);
          final fileName = fileMap['name'] as String;
          final fileUri = fileMap['uri'] as String;
          final lastModified = fileMap['lastModified'] as int;
          final fileType = fileMap['type'] as String;
          final isVideo = fileType.startsWith('video/');

          // Track the latest timestamp
          if (lastModified > latestTimestamp) {
            latestTimestamp = lastModified;
          }

          // 🆕 Check if file already exists in gallery
          final alreadyExists = await platform.invokeMethod('checkFileExistsInGallery', {
            'fileName': fileName,
            'isVideo': isVideo,
          });

          if (alreadyExists == true) {
            alreadyExistCount++;
            continue; // Skip if already saved
          }

          // Read file bytes from URI
          final bytes = await platform.invokeMethod('readFileBytes', {
            'uri': fileUri,
          });

          if (bytes != null) {
            // 🆕 Save to gallery using MediaStore
            final success = await platform.invokeMethod('saveToGallery', {
              'bytes': bytes,
              'fileName': fileName,
              'isVideo': isVideo,
            });

            if (success == true) {
              savedCount++;
            }
          }
        } catch (e) {
          print('Error saving individual file: $e');
        }
      }

      // ✅ Small delay between batches to prevent blocking
      if (i + batchSize < files.length) {
        await Future.delayed(Duration(milliseconds: 50));
      }
    }

    // Update last seen timestamp
    final key = 'last_seen_${isBusiness ? "business" : "regular"}';
    await prefs.setInt(key, latestTimestamp);

    print(
      '✅ Auto-save: Saved $savedCount files from ${isBusiness ? "Business" : "Regular"} WhatsApp${alreadyExistCount > 0 ? " ($alreadyExistCount already existed)" : ""}',
    );
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

/// Check and save new statuses from a specific URI - NOW SAVES TO GALLERY
Future<void> _checkAndSaveNewStatuses(
    String folderUri,
    bool isBusiness,
    SharedPreferences prefs,
    ) async {
  try {
    // Get current files from URI
    final List<dynamic> files = await platform.invokeMethod('getFilesFromUri', {
      'uri': folderUri,
      'isBusiness': isBusiness ? 'true' : 'false',
    });

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

    int savedCount = 0;
    int alreadyExistCount = 0;
    int latestTimestamp = lastSeen;

    for (var file in newFiles) {
      try {
        final fileMap = Map<String, dynamic>.from(file);
        final fileName = fileMap['name'] as String;
        final fileUri = fileMap['uri'] as String;
        final lastModified = fileMap['lastModified'] as int;
        final fileType = fileMap['type'] as String;
        final isVideo = fileType.startsWith('video/');

        // Track latest timestamp
        if (lastModified > latestTimestamp) {
          latestTimestamp = lastModified;
        }

        // 🆕 Check if file already exists in gallery
        final alreadyExists = await platform.invokeMethod('checkFileExistsInGallery', {
          'fileName': fileName,
          'isVideo': isVideo,
        });

        if (alreadyExists == true) {
          alreadyExistCount++;
          continue;
        }

        // Read and save file
        final bytes = await platform.invokeMethod('readFileBytes', {
          'uri': fileUri,
        });

        if (bytes != null) {
          // 🆕 Save to gallery using MediaStore
          final success = await platform.invokeMethod('saveToGallery', {
            'bytes': bytes,
            'fileName': fileName,
            'isVideo': isVideo,
          });

          if (success == true) {
            savedCount++;
            print('📥 Auto-saved to Gallery: $fileName');
          }
        }
      } catch (e) {
        print('Error auto-saving file: $e');
      }
    }

    // Update last seen timestamp
    if (latestTimestamp > lastSeen) {
      await prefs.setInt(key, latestTimestamp);
    }

    if (savedCount > 0 || alreadyExistCount > 0) {
      print(
        '✅ Auto-saved $savedCount new ${isBusiness ? "Business" : "Regular"} statuses to Gallery${alreadyExistCount > 0 ? " ($alreadyExistCount already existed)" : ""}',
      );
    }
  } catch (e) {
    print('❌ Error in _checkAndSaveNewStatuses: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('🚀 [main] App starting...');

  // Initialize Mobile Ads first
  MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(testDeviceIds: ["09357ABB7CD78370747E779FBA319F0F"]),
  );
  await MobileAds.instance.initialize();
  print('✅ [main] Mobile Ads initialized');

  // Initialize Subscription Service
  final subService = SubscriptionService();
  await subService.init();
  print('✅ [main] Subscription Service initialized');

  // 🔥 Initialize Global Ads Controller AFTER subscription service
  // This ensures the subscription stream is ready before ads controller subscribes
  await AdsController.instance.init();
  print('✅ [main] Ads Controller initialized');

  // Load interstitial ad only if not premium
  final isPremium = await SubscriptionService.isPremium();
  if (!isPremium) {
    InterstitialService.loadAd();
    print('📢 [main] Loading interstitial ad (user is not premium)');
  } else {
    print('🎉 [main] User is premium, skipping interstitial ad');
  }

  // Request permissions
  await Permission.storage.request();
  await Permission.manageExternalStorage.request();
  print('✅ [main] Permissions requested');

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

      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.teal,
        ),
      ),

      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
        ),
      ),

      home: StatusApp(
        isDarkTheme: _isDarkTheme,
        onThemeChanged: _toggleTheme,
      ),
    );
  }
}

class StatusApp extends StatefulWidget {
  final bool isDarkTheme;
  final Function(bool) onThemeChanged;

  const StatusApp({
    super.key,
    required this.isDarkTheme,
    required this.onThemeChanged,
  });

  @override
  State<StatusApp> createState() => _StatusAppState();
}

class _StatusAppState extends State<StatusApp> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  Timer? _statusCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Check for new statuses every 10 seconds
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await checkStatusesForeground();
    });

    print('✅ [StatusApp] Initialized');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusCheckTimer?.cancel();
    print('🗑️ [StatusApp] Disposed');
    super.dispose();
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

    // 🔥 Get banner from global AdsController
    final adsController = AdsController.instance;

    return Scaffold(
      body: _build(_selectedIndex),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🔥 USE ValueListenableBuilder to rebuild when banner status changes
          ValueListenableBuilder<bool>(
            valueListenable: adsController.bannerStatusNotifier,
            builder: (context, hasBanner, child) {
              // Only show banner if it's loaded and available
              if (hasBanner && adsController.bannerAd != null) {
                print('📱 [UI] Displaying banner ad');
                return Container(
                  width: adsController.bannerAd!.size.width.toDouble(),
                  height: adsController.bannerAd!.size.height.toDouble(),
                  alignment: Alignment.center,
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: AdWidget(ad: adsController.bannerAd!),
                );
              }
              // Return empty container if no banner
              print('📱 [UI] No banner to display');
              return const SizedBox.shrink();
            },
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
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat),
                  label: "Whatsapp",
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.business),
                  label: "Business",
                ),
                BottomNavigationBarItem(icon: Icon(Icons.save), label: "Saved"),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: "Settings",
                ),
              ],
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.white70,
              backgroundColor: Colors.transparent,
              currentIndex: _selectedIndex,
              onTap: (index) => setState(() => _selectedIndex = index),
            ),
          ),
        ],
      ),
    );
  }
}