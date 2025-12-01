import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_bank/saved_page.dart';
import 'package:status_bank/setting_page.dart';
import 'package:status_bank/status_tab_page.dart';
import 'package:status_bank/status_tab_papge2.dart';


import 'interstitial_ad_service.dart';




/*final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();*/

const List<Map<String, String>> statusFolders = [
  {
    'source':
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses',
    'sub': 'WhatsApp'
  },
  {
    'source':
    '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses',
    'sub': 'BusinessWhatsApp'
  },
];



/// Background task (WorkManager)
/*void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bgNotificationsEnabled =
          prefs.getBool('enabled_notification') ?? false;
      final bgAutoSaveEnabled = prefs.getBool('enabled_auto_save') ?? false;

      final FlutterLocalNotificationsPlugin bgNotifPlugin =
      FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await bgNotifPlugin.initialize(initSettings);

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'status_channel',
        'Status Updates',
        description: 'Notifies when new WhatsApp statuses appear',
        importance: Importance.high,
      );

      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
      bgNotifPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(channel);

      int totalNewFiles = 0;

      for (final f in statusFolders) {
        final sourcePath = f['source']!;
        final sourceDir = Directory(sourcePath);

        if (!await sourceDir.exists()) continue;

        final allFiles = sourceDir
            .listSync()
            .whereType<File>()
            .where((file) =>
        file.path.toLowerCase().endsWith('.jpg') ||
            file.path.toLowerCase().endsWith('.jpeg') ||
            file.path.toLowerCase().endsWith('.mp4'))
            .toList();

        if (allFiles.isEmpty) continue;

        allFiles.sort((a, b) =>
            a.statSync().modified.compareTo(b.statSync().modified)); // asc
        final latest = allFiles.last;
        final latestMillis = latest.statSync().modified.millisecondsSinceEpoch;

        final key = 'last_seen_${sourcePath.hashCode}';
        final lastSeen = prefs.getInt(key) ?? 0;

        if (latestMillis > lastSeen) {
          final newFiles = allFiles
              .where((file) =>
          file.statSync().modified.millisecondsSinceEpoch > lastSeen)
              .toList();

          if (bgAutoSaveEnabled) {
            final targetDir = Directory('/storage/emulated/0/StatusSaver');
            if (!targetDir.existsSync()) targetDir.createSync(recursive: true);

            for (final file in newFiles) {
              try {
                final destPath =
                    '${targetDir.path}/${file.uri.pathSegments.last}';
                if (!File(destPath).existsSync()) {
                  await file.copy(destPath);
                }
              } catch (e) {
                print('Background copy error: $e');
              }
            }
          }

          if (bgNotificationsEnabled && newFiles.isNotEmpty) {
            try {
              const androidDetails = AndroidNotificationDetails(
                'status_channel',
                'Status Updates',
                channelDescription:
                'Notifies when new WhatsApp statuses appear',
                importance: Importance.high,
                priority: Priority.high,
              );
              const details = NotificationDetails(android: androidDetails);
              await bgNotifPlugin.show(
                0,
                'New Status${newFiles.length > 1 ? 'es' : ''} Found',
                bgAutoSaveEnabled
                    ? '${newFiles.length} new status(es) auto-saved'
                    : '${newFiles.length} new status(es) available',
                details,
              );
            } catch (e) {
              print('Background notification error: $e');
            }
          }

          totalNewFiles += newFiles.length;
          await prefs.setInt(key, latestMillis);
        }
      }

      print('Background task finished: new files = $totalNewFiles');
      return Future.value(true);
    } catch (e) {
      print('Background worker error: $e');
      return Future.value(true);
    }
  });
}
*/
/// Foreground auto-save (called when user enables Auto Save)
Future<void> saveAllExistingStatusesForeground() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final f in statusFolders) {
      final sourcePath = f['source']!;
      final sourceDir = Directory(sourcePath);

      if (!await sourceDir.exists()) continue;

      final allFiles = sourceDir
          .listSync()
          .whereType<File>()
          .where((file) =>
      file.path.toLowerCase().endsWith('.jpg') ||
          file.path.toLowerCase().endsWith('.jpeg') ||
          file.path.toLowerCase().endsWith('.mp4'))
          .toList();

      if (allFiles.isEmpty) continue;

      final targetDir = Directory('/storage/emulated/0/StatusSaver');
      if (!targetDir.existsSync()) targetDir.createSync(recursive: true);

      for (final file in allFiles) {
        try {
          final destPath = '${targetDir.path}/${file.uri.pathSegments.last}';
          if (!File(destPath).existsSync()) {
            await file.copy(destPath);
          }
        } catch (e) {
          print('Foreground copy error: $e');
        }
      }

      allFiles.sort((a, b) =>
          a.statSync().modified.compareTo(b.statSync().modified));
      final latest = allFiles.last;
      final key = 'last_seen_${sourcePath.hashCode}';
      await prefs.setInt(
          key, latest.statSync().modified.millisecondsSinceEpoch);
    }
  } catch (e) {
    print('saveAllExistingStatusesForeground error: $e');
  }
}

Future<void> checkStatusesForeground() async {
  final prefs = await SharedPreferences.getInstance();
  final notificationsEnabled = prefs.getBool('enabled_notification') ?? false;
  final autoSaveEnabled = prefs.getBool('enabled_auto_save') ?? false;

  for (final f in statusFolders) {
    final sourcePath = f['source']!;
    final sourceDir = Directory(sourcePath);

    if (!await sourceDir.exists()) continue;

    final allFiles = sourceDir
        .listSync()
        .whereType<File>()
        .where((file) =>
    file.path.toLowerCase().endsWith('.jpg') ||
        file.path.toLowerCase().endsWith('.jpeg') ||
        file.path.toLowerCase().endsWith('.mp4'))
        .toList();

    if (allFiles.isEmpty) continue;

    allFiles.sort((a, b) =>
        a.statSync().modified.compareTo(b.statSync().modified)); // asc
    final latest = allFiles.last;
    final latestMillis = latest.statSync().modified.millisecondsSinceEpoch;
    final key = 'last_seen_${sourcePath.hashCode}';
    final lastSeen = prefs.getInt(key) ?? 0;

    if (latestMillis > lastSeen) {
      final newFiles = allFiles
          .where((file) =>
      file.statSync().modified.millisecondsSinceEpoch > lastSeen)
          .toList();

      if (autoSaveEnabled) {
        final targetDir = Directory('/storage/emulated/0/StatusSaver');
        if (!targetDir.existsSync()) targetDir.createSync(recursive: true);

        for (final file in newFiles) {
          final destPath = '${targetDir.path}/${file.uri.pathSegments.last}';
          if (!File(destPath).existsSync()) {
            await file.copy(destPath);
          }
        }
      }

      /* if (notificationsEnabled && newFiles.isNotEmpty) {
        const androidDetails = AndroidNotificationDetails(
          'status_channel',
          'Status Updates',
          channelDescription: 'Notifies when new WhatsApp statuses appear',
          importance: Importance.high,
          priority: Priority.high,
        );
        const details = NotificationDetails(android: androidDetails);
        await flutterLocalNotificationsPlugin.show(
          0,
          'New Status${newFiles.length > 1 ? 'es' : ''} Found',
          autoSaveEnabled
              ? '${newFiles.length} new status(es) auto-saved'
              : '${newFiles.length} new status(es) available',
          details,
        );
      } */

      await prefs.setInt(key, latestMillis);
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  InterstitialService.loadAd();
  MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(
      testDeviceIds: ["09357ABB7CD78370747E779FBA319F0F"],
    ),
  );
  await MobileAds.instance.initialize();

  await Permission.storage.request();
  await Permission.manageExternalStorage.request();
  // await Permission.notification.request();
/*
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: android);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'status_channel',
    'Status Updates',
    description: 'Notifies when new WhatsApp statuses appear',
    importance: Importance.high,
  );
  final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
  flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(channel);

 */

  /* await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  await Workmanager().registerPeriodicTask(
    "checkStatusUpdates",
    "checkStatusTask",
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );

  */

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

class _StatusAppState extends State<StatusApp> {
  int _selectedIndex = 0;
  Timer? _timer;
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;


  @override
  void initState() {
    super.initState();
    _loadBannnerAds();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await checkStatusesForeground();
    });
  }


  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
    _bannerAd?.dispose();
  }

  void _loadBannnerAds(){
    print("📢 Loading Banner Ad...");
    final String AdUnitId = Platform.isAndroid ? "ca-app-pub-3940256099942544/9214589741" : "ca-app-pub-3940256099942544/2435281174";
    final BannerAd banner = BannerAd(
        size: AdSize.banner,
        adUnitId: AdUnitId,
        listener: BannerAdListener(onAdLoaded:
            (ad) {
          print("✅ Banner Ad Loaded Successfully!");
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerAdReady = true;
          });
        },
          onAdFailedToLoad: (ad, error){
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
        bottomNavigationBar:  Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isBannerAdReady && _bannerAd != null)
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
