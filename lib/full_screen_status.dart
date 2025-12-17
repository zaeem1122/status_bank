import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:status_bank/widget.dart';
import 'package:video_player/video_player.dart';

import 'interstitial_ad_service.dart';
import 'subscription_service.dart';

class FullScreenStatusOptimized extends StatefulWidget {
  final List<Map<String, dynamic>> allFilesMetadata;
  final int initialIndex;
  final MethodChannel platform;
  final bool isBusiness; // ✅ Add parameter to distinguish Business WhatsApp

  const FullScreenStatusOptimized({
    super.key,
    required this.allFilesMetadata,
    required this.initialIndex,
    required this.platform,
    this.isBusiness = false, // ✅ Default to false (regular WhatsApp)
  });

  @override
  State<FullScreenStatusOptimized> createState() => _FullScreenStatusOptimizedState();
}

class _FullScreenStatusOptimizedState extends State<FullScreenStatusOptimized> {
  late PageController _pageController;
  int currentIndex = 0;
  bool _isPremium = false; // ✅ Track premium status
  String? _saveDirPath; // ✅ Save directory path

  // Cache for loaded files (only loads what's needed)
  final Map<int, String> _loadedFilePaths = {};
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, bool> _isLoadingFile = {};

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _checkPremiumStatus(); // ✅ Check premium status
    _initializeSaveDirectory(); // ✅ Initialize save directory

    // Load only current and adjacent files
    _loadFile(currentIndex);
    _preloadFile(currentIndex - 1);
    _preloadFile(currentIndex + 1);
  }

  // ✅ Check if user is premium
  Future<void> _checkPremiumStatus() async {
    final isPremium = await SubscriptionService.isPremium();
    setState(() {
      _isPremium = isPremium;
    });
  }

  // ✅ Initialize save directory based on Business or Regular WhatsApp
  Future<void> _initializeSaveDirectory() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _getAndroidVersion();

        if (androidInfo >= 30) {
          // Android 10+ (API 29+): Use app-specific external directory
          final dir = await getExternalStorageDirectory();
          if (dir != null) {
            // ✅ Create Business subfolder if isBusiness is true
            final saveDir = widget.isBusiness
                ? Directory('${dir.path}/StatusSaver/Business')
                : Directory('${dir.path}/StatusSaver');

            if (!await saveDir.exists()) {
              await saveDir.create(recursive: true);
            }
            _saveDirPath = saveDir.path;
            print('📁 Save directory: $_saveDirPath');
          }
        } else {
          // Android 9 and below: Use public directory
          _saveDirPath = widget.isBusiness
              ? "/storage/emulated/0/StatusSaver/Business"
              : "/storage/emulated/0/StatusSaver";
        }
      }
    } catch (e) {
      print('❌ Error initializing save directory: $e');
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        _saveDirPath = widget.isBusiness
            ? '${dir.path}/StatusSaver/Business'
            : '${dir.path}/StatusSaver';
      }
    }
  }

  // ✅ Get Android version
  Future<int> _getAndroidVersion() async {
    try {
      final version = await widget.platform.invokeMethod('getAndroidVersion');
      return version as int;
    } catch (e) {
      return 30;
    }
  }

  // ✅ Load file on demand from URI
  Future<void> _loadFile(int index) async {
    if (index < 0 || index >= widget.allFilesMetadata.length) return;
    if (_loadedFilePaths.containsKey(index)) return;
    if (_isLoadingFile[index] == true) return;

    setState(() => _isLoadingFile[index] = true);

    try {
      final fileMap = widget.allFilesMetadata[index];
      final uri = fileMap['uri'] as String;
      final fileName = fileMap['name'] as String;

      // Use cache directory for temporary file
      final cacheDir = await getTemporaryDirectory();
      final tempDir = Directory("${cacheDir.path}/fullscreen_cache");

      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      final tempPath = "${tempDir.path}/$fileName";
      final tempFile = File(tempPath);

      // Check if file already exists in cache
      if (await tempFile.exists()) {
        _loadedFilePaths[index] = tempPath;
        _initVideoController(index, tempPath);
        if (mounted) setState(() => _isLoadingFile[index] = false);
        return;
      }

      // Load file bytes from URI
      final bytes = await widget.platform.invokeMethod('readFileBytes', {'uri': uri});

      if (bytes != null) {
        await tempFile.writeAsBytes(bytes);
        _loadedFilePaths[index] = tempPath;

        // Initialize video controller if it's a video
        _initVideoController(index, tempPath);
      }
    } catch (e) {
      print('Error loading file at index $index: $e');
    } finally {
      if (mounted) setState(() => _isLoadingFile[index] = false);
    }
  }

  // Preload without blocking
  Future<void> _preloadFile(int index) async {
    if (index < 0 || index >= widget.allFilesMetadata.length) return;
    if (_loadedFilePaths.containsKey(index)) return;

    // Don't await - let it load in background
    _loadFile(index);
  }

  void _initVideoController(int index, String path) {
    if (!path.endsWith(".mp4") && !path.endsWith(".3gp")) return;
    if (_videoControllers.containsKey(index)) return;

    final controller = VideoPlayerController.file(File(path));
    _videoControllers[index] = controller;

    controller.initialize().then((_) {
      if (mounted && currentIndex == index) {
        controller.play();
        controller.setLooping(false);
        setState(() {});
      }
    }).catchError((error) {
      print("Error initializing video: $error");
    });
  }

  void _cleanupDistantFiles(int currentPage) {
    final toRemove = <int>[];

    _loadedFilePaths.forEach((index, path) {
      if ((index - currentPage).abs() > 2) {
        toRemove.add(index);
      }
    });

    for (var index in toRemove) {
      // Dispose video controller
      _videoControllers[index]?.dispose();
      _videoControllers.remove(index);

      // Delete cached file
      try {
        final file = File(_loadedFilePaths[index]!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        print('Error deleting cached file: $e');
      }

      _loadedFilePaths.remove(index);
    }
  }

  @override
  void dispose() {
    for (var c in _videoControllers.values) {
      c.dispose();
    }
    _pageController.dispose();

    // Clean up all cached files
    _cleanupAllCachedFiles();
    super.dispose();
  }

  Future<void> _cleanupAllCachedFiles() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final tempDir = Directory("${cacheDir.path}/fullscreen_cache");
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (e) {
      print('Error cleaning up cache: $e');
    }
  }

  // ✅ FIXED: saveFile method with proper file existence checking using original filename
  Future<void> saveFile(int index) async {
    if (!_loadedFilePaths.containsKey(index)) {
      showCustomOverlay(context, "File not loaded yet");
      return;
    }

    try {
      if (_saveDirPath == null) {
        await _initializeSaveDirectory();
      }

      if (_saveDirPath == null) {
        showCustomOverlay(context, "Failed to access storage");
        return;
      }

      final file = File(_loadedFilePaths[index]!);
      final dir = Directory(_saveDirPath!);

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // ✅ FIX: Use the original file name from metadata instead of temp cache name
      final fileMap = widget.allFilesMetadata[index];
      final originalFileName = fileMap['name'] as String;

      final savedPath = "${dir.path}/$originalFileName";
      final savedFile = File(savedPath);

      // ✅ FIX: Check if file already exists with same name and similar size
      if (await savedFile.exists()) {
        final existingSize = await savedFile.length();
        final currentSize = await file.length();

        // If file exists and has similar size (within 1KB difference), it's already saved
        if ((existingSize - currentSize).abs() < 1024) {
          showCustomOverlay(context, "File Already Downloaded");
          return;
        }
      }

      await file.copy(savedPath);

      // Verify file was saved
      if (await savedFile.exists()) {
        final fileSize = await savedFile.length();
        print('✅ File saved successfully: $savedPath (${fileSize} bytes)');

        // ✅ Show appropriate message based on Business or Regular
        final message = widget.isBusiness
            ? "Saved to StatusSaver/Business folder"
            : "Saved to StatusSaver folder";
        showCustomOverlay(context, message);
      } else {
        showCustomOverlay(context, "Failed to save file");
      }
    } catch (e) {
      print('❌ Error saving file: $e');
      showCustomOverlay(context, "Failed to save: ${e.toString().contains('Operation not permitted') ? 'Storage access denied' : 'Error'}");
    }
  }

  Widget _buildContent(int index) {
    // Check if file is loaded
    if (!_loadedFilePaths.containsKey(index)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    final path = _loadedFilePaths[index]!;
    final isVideo = path.endsWith(".mp4") || path.endsWith(".3gp");

    if (isVideo) {
      final controller = _videoControllers[index];
      if (controller != null && controller.value.isInitialized) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
            Container(
              color: Colors.black.withOpacity(0.7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          controller.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          setState(() {
                            controller.value.isPlaying
                                ? controller.pause()
                                : controller.play();
                          });
                        },
                      ),
                      Expanded(
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Colors.teal,
                            backgroundColor: Colors.grey,
                          ),
                        ),
                      ),
                      ValueListenableBuilder(
                        valueListenable: controller,
                        builder: (context, VideoPlayerValue value, _) {
                          String fmt(Duration d) =>
                              "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
                          return Text(
                            "${fmt(value.position)} / ${fmt(value.duration)}",
                            style: const TextStyle(color: Colors.white),
                          );
                        },
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: () async {
                          // ✅ Only show ad if user is not premium
                          if (!_isPremium) {
                            InterstitialService.show();
                          }
                          await Share.shareXFiles([XFile(path)]);
                        },
                        icon: const Icon(Icons.share, color: Colors.white),
                      ),
                      IconButton(
                        onPressed: () async {
                          // ✅ Only show ad if user is not premium
                          if (!_isPremium) {
                            InterstitialService.show();
                          }
                          await saveFile(index);
                        },
                        icon: const Icon(Icons.download, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      } else {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
    } else {
      // Image
      return Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(Icons.error, color: Colors.white, size: 48),
                  );
                },
              ),
            ),
          ),
          Container(
            color: Colors.black.withOpacity(0.7),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () async {
                    // ✅ Only show ad if user is not premium
                    if (!_isPremium) {
                      InterstitialService.show();
                    }
                    await Share.shareXFiles([XFile(path)]);
                  },
                  icon: const Icon(Icons.share, color: Colors.white),
                ),
                IconButton(
                  onPressed: () async {
                    // ✅ Only show ad if user is not premium
                    if (!_isPremium) {
                      InterstitialService.show();
                    }
                    await saveFile(index);
                  },
                  icon: const Icon(Icons.download, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Status Saver",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black87,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.allFilesMetadata.length,
        onPageChanged: (index) {
          // Pause current video
          if (_videoControllers.containsKey(currentIndex)) {
            _videoControllers[currentIndex]?.pause();
          }

          setState(() => currentIndex = index);

          // Load current and adjacent files
          _loadFile(index);
          _preloadFile(index - 1);
          _preloadFile(index + 1);

          // Cleanup distant files
          _cleanupDistantFiles(index);
        },
        itemBuilder: (context, index) {
          return _buildContent(index);
        },
      ),
    );
  }
}