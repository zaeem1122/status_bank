import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_bank/video_preview.dart';
import 'package:status_bank/widget.dart';

import 'chat_screen.dart';
import 'full_screen_status.dart';
import 'interstitial_ad_service.dart';
import 'subscription_service.dart';

class StatusTabPage extends StatefulWidget {
  final String title;
  const StatusTabPage({super.key, required this.title});

  @override
  State<StatusTabPage> createState() => _StatusTabPageState();
}

class _StatusTabPageState extends State<StatusTabPage>
    with SingleTickerProviderStateMixin {
  static const platform = MethodChannel('com.yourapp/status_access');

  String? _saveDirPath;

  List<Map<String, dynamic>> imageFiles = [];
  List<Map<String, dynamic>> videoFiles = [];

  String? savedFolderUri;
  bool isLoading = true;
  bool showPermissionScreen = false;
  bool _isPremium = false;

  // Multi-select variables
  List<String> selectedPaths = [];
  bool selectionMode = false;

  // ✅ Cache for loaded media to prevent reloading
  final Map<String, dynamic> _mediaCache = {};

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
    _initializeSaveDirectory();
    _checkInitialState();
  }

  Future<void> _checkPremiumStatus() async {
    final isPremium = await SubscriptionService.isPremium();
    setState(() {
      _isPremium = isPremium;
    });
  }

  Future<void> _initializeSaveDirectory() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _getAndroidVersion();

        if (androidInfo >= 30) {
          final dir = await getExternalStorageDirectory();
          if (dir != null) {
            final saveDir = Directory('${dir.path}/StatusSaver');
            if (!await saveDir.exists()) {
              await saveDir.create(recursive: true);
            }
            _saveDirPath = saveDir.path;
            print('📁 Save directory: $_saveDirPath');
          }
        } else {
          _saveDirPath = "/storage/emulated/0/StatusSaver";
        }
      }
    } catch (e) {
      print('❌ Error initializing save directory: $e');
      final dir = await getExternalStorageDirectory();
      _saveDirPath = dir?.path ?? '';
    }
  }

  Future<void> _checkInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    savedFolderUri = prefs.getString('status_folder_uri');

    if (savedFolderUri != null) {
      await _loadFilesFromSavedUri();
    } else {
      setState(() {
        showPermissionScreen = true;
        isLoading = false;
      });
      await _requestStoragePermission();
    }
  }

  Future<void> _requestStoragePermission() async {
    setState(() => isLoading = true);

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _getAndroidVersion();

        PermissionStatus status;

        if (androidInfo >= 33) {
          Map<Permission, PermissionStatus> statuses = await [
            Permission.photos,
            Permission.videos,
          ].request();
          status = statuses[Permission.photos] ?? PermissionStatus.denied;
        } else if (androidInfo >= 30) {
          status = await Permission.storage.request();
        } else {
          status = await Permission.storage.request();
        }

        if (status.isGranted || status.isLimited) {
          await Future.delayed(Duration(milliseconds: 500));
          await _proceedToFolderSelection();
        } else {
          setState(() => isLoading = false);
          await _proceedToFolderSelection();
        }
      }
    } catch (e) {
      print('Error requesting permission: $e');
      setState(() => isLoading = false);
      await _proceedToFolderSelection();
    }
  }

  Future<int> _getAndroidVersion() async {
    try {
      final version = await platform.invokeMethod('getAndroidVersion');
      return version as int;
    } catch (e) {
      return 30;
    }
  }

  Future<void> _proceedToFolderSelection() async {
    try {
      setState(() => isLoading = true);

      final String? folderUri = await platform.invokeMethod('openStatusFolderPicker');

      if (folderUri != null && folderUri.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('status_folder_uri', folderUri);
        savedFolderUri = folderUri;

        await platform.invokeMethod('takePersistablePermission', {'uri': folderUri});

        setState(() => showPermissionScreen = false);
        await _loadFilesFromSavedUri();
      } else {
        setState(() => isLoading = false);
      }
    } on PlatformException catch (e) {
      print('Platform error: ${e.code} - ${e.message}');
      setState(() => isLoading = false);
    } catch (e) {
      print('Error opening folder picker: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadFilesFromSavedUri() async {
    if (savedFolderUri == null) return;

    try {
      setState(() => isLoading = true);

      final List<dynamic> files = await platform.invokeMethod(
          'getFilesFromUri',
          {'uri': savedFolderUri, 'isBusiness': 'false'}
      );

      List<Map<String, dynamic>> images = [];
      List<Map<String, dynamic>> videos = [];

      for (var file in files) {
        final fileMap = Map<String, dynamic>.from(file);
        final type = fileMap['type'] as String;

        if (type.startsWith('image/')) {
          images.add(fileMap);
        } else if (type.startsWith('video/')) {
          videos.add(fileMap);
        }
      }

      images.sort((a, b) => (b['lastModified'] as int).compareTo(a['lastModified'] as int));
      videos.sort((a, b) => (b['lastModified'] as int).compareTo(a['lastModified'] as int));

      setState(() {
        imageFiles = images;
        videoFiles = videos;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading files: $e');
      setState(() => isLoading = false);
      _showErrorDialog('Could not find status files.\n\nMake sure you selected the "com.whatsapp" folder.');
    }
  }

  // ✅ Cache-aware image loading
  Future<Uint8List?> _loadImageBytes(String uriString) async {
    // Check cache first
    if (_mediaCache.containsKey(uriString) && _mediaCache[uriString] is Uint8List) {
      return _mediaCache[uriString] as Uint8List;
    }

    try {
      final bytes = await platform.invokeMethod('readFileBytes', {'uri': uriString});
      if (bytes != null) {
        _mediaCache[uriString] = bytes as Uint8List; // Cache it
        return bytes as Uint8List;
      }
      return null;
    } catch (e) {
      print('Error loading image: $e');
      return null;
    }
  }

  // ✅ Cache-aware video loading
  Future<String?> _getVideoFilePath(String uriString) async {
    // Check cache first
    if (_mediaCache.containsKey(uriString) && _mediaCache[uriString] is String) {
      final cachedPath = _mediaCache[uriString] as String;
      if (await File(cachedPath).exists()) {
        return cachedPath;
      } else {
        _mediaCache.remove(uriString); // Remove invalid cache
      }
    }

    try {
      final cacheDir = await getTemporaryDirectory();
      final videoDir = Directory("${cacheDir.path}/video_previews");

      if (!await videoDir.exists()) {
        await videoDir.create(recursive: true);
      }

      final fileName = uriString.split('/').last.split('?').first;
      final localPath = "${videoDir.path}/$fileName";
      final localFile = File(localPath);

      if (await localFile.exists()) {
        _mediaCache[uriString] = localPath; // Cache it
        return localPath;
      }

      final bytes = await platform.invokeMethod('readFileBytes', {'uri': uriString});
      if (bytes != null) {
        await localFile.writeAsBytes(bytes);
        _mediaCache[uriString] = localPath; // Cache it
        return localPath;
      }

      return null;
    } catch (e) {
      print('Error getting video file path: $e');
      return null;
    }
  }

  Future<void> saveFile(Map<String, dynamic> fileMap) async {
    try {
      if (_saveDirPath == null) {
        await _initializeSaveDirectory();
      }

      if (_saveDirPath == null) {
        showCustomOverlay(context, "Failed to access storage");
        return;
      }

      final dir = Directory(_saveDirPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final fileName = fileMap['name'] as String;
      final savedPath = "${dir.path}/$fileName";
      final savedFile = File(savedPath);

      if (await savedFile.exists()) {
        showCustomOverlay(
          context,
          fileMap['type'].toString().startsWith('video/')
              ? "Video Already Downloaded"
              : "Image Already Downloaded",
        );
        return;
      }

      final bytes = await platform.invokeMethod('readFileBytes', {'uri': fileMap['uri']});

      if (bytes == null) {
        showCustomOverlay(context, "Failed to read file");
        return;
      }

      await savedFile.writeAsBytes(bytes as Uint8List);

      if (await savedFile.exists()) {
        final fileSize = await savedFile.length();
        print('✅ File saved successfully: $savedPath (${fileSize} bytes)');
        showCustomOverlay(context, "File Saved Successfully");
      } else {
        showCustomOverlay(context, "Failed to save file");
      }
    } catch (e) {
      print('❌ Error saving file: $e');
      showCustomOverlay(context, "Failed to save: ${e.toString().contains('Operation not permitted') ? 'Storage access denied' : 'Error'}");
    }
  }

  void toggleSelect(String uri) {
    setState(() {
      if (selectedPaths.contains(uri)) {
        selectedPaths.remove(uri);
        if (selectedPaths.isEmpty) selectionMode = false;
      } else {
        selectedPaths.add(uri);
        selectionMode = true;
      }
    });
  }

  void deselectAll() {
    setState(() {
      selectedPaths.clear();
      selectionMode = false;
    });
  }

  Future<void> downloadSelectedFiles() async {
    if (selectedPaths.isEmpty) return;

    try {
      if (_saveDirPath == null) {
        await _initializeSaveDirectory();
      }

      if (_saveDirPath == null) {
        showCustomOverlay(context, "Failed to access storage");
        return;
      }

      final dir = Directory(_saveDirPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      int savedCount = 0;
      int alreadyExistCount = 0;
      int failedCount = 0;

      for (var uri in selectedPaths) {
        try {
          final fileMap = [...imageFiles, ...videoFiles].firstWhere((f) => f['uri'] == uri);
          final fileName = fileMap['name'] as String;
          final savedPath = "${dir.path}/$fileName";
          final savedFile = File(savedPath);

          if (await savedFile.exists()) {
            alreadyExistCount++;
          } else {
            final bytes = await platform.invokeMethod('readFileBytes', {'uri': uri});
            if (bytes != null) {
              await savedFile.writeAsBytes(bytes as Uint8List);

              if (await savedFile.exists()) {
                savedCount++;
                print('✅ Saved: $fileName');
              } else {
                failedCount++;
              }
            } else {
              failedCount++;
            }
          }
        } catch (e) {
          print('❌ Error saving file: $e');
          failedCount++;
        }
      }

      selectedPaths.clear();
      selectionMode = false;
      setState(() {});

      if (savedCount > 0 && alreadyExistCount > 0) {
        showCustomOverlay(context, "$savedCount saved, $alreadyExistCount already existed");
      } else if (savedCount > 0) {
        showCustomOverlay(context, "$savedCount files saved to StatusSaver");
      } else if (alreadyExistCount > 0) {
        showCustomOverlay(context, "All files already downloaded");
      } else if (failedCount > 0) {
        showCustomOverlay(context, "Failed to save $failedCount files");
      }
    } catch (e) {
      print('❌ Error in downloadSelectedFiles: $e');
      showCustomOverlay(context, "Failed to save files");
    }
  }

  Future<void> shareSelectedFiles() async {
    if (selectedPaths.isEmpty) return;

    final cacheDir = await getTemporaryDirectory();
    final tempDir = Directory("${cacheDir.path}/share_temp");

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);

    List<XFile> xfiles = [];

    for (var uri in selectedPaths) {
      try {
        final fileMap = [...imageFiles, ...videoFiles].firstWhere((f) => f['uri'] == uri);
        final fileName = fileMap['name'] as String;
        final tempPath = "${tempDir.path}/$fileName";

        final bytes = await platform.invokeMethod('readFileBytes', {'uri': uri});
        if (bytes != null) {
          final tempFile = File(tempPath);
          await tempFile.writeAsBytes(bytes);
          xfiles.add(XFile(tempPath));
        }
      } catch (e) {
        print('Error preparing file for share: $e');
      }
    }

    if (xfiles.isNotEmpty) {
      await Share.shareXFiles(xfiles, text: "Sharing multiple statuses");
    }

    selectedPaths.clear();
    selectionMode = false;
    setState(() {});
  }

  Future<void> _openFullScreen(int index, List<Map<String, dynamic>> currentFiles) async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenStatusOptimized(
            allFilesMetadata: currentFiles,
            initialIndex: index,
            platform: platform,
          ),
        ),
      );
    } catch (e) {
      print('Error in _openFullScreen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file: $e')),
        );
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget buildGrid(List<Map<String, dynamic>> files, bool isImage) {
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
        ),
      );
    }

    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isImage ? Icons.image : Icons.video_collection,
                size: 70, color: Colors.teal),
            SizedBox(height: 16),
            Text(
              isImage ? "No Image Status Found" : "No Video Status Found",
              style: const TextStyle(fontSize: 15, color: Colors.teal),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadFilesFromSavedUri,
              icon: Icon(Icons.refresh),
              label: Text('Refresh'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: files.length,
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      cacheExtent: 500,
      itemBuilder: (context, index) {
        final fileMap = files[index];
        final uri = fileMap['uri'] as String;
        final isVideo = fileMap['type'].toString().startsWith('video/');

        // ✅ Use unique key for each card to preserve state
        return Card(
          key: ValueKey(uri),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 4,
          child: _MediaThumbnail(
            uri: uri,
            isVideo: isVideo,
            isSelected: selectedPaths.contains(uri),
            selectionMode: selectionMode,
            isPremium: _isPremium,
            onTap: () {
              if (selectionMode) {
                toggleSelect(uri);
                return;
              }
              _openFullScreen(index, files);
            },
            onLongPress: () => toggleSelect(uri),
            onDownload: () {
              if (!_isPremium) {
                InterstitialService.show();
              }
              saveFile(fileMap);
            },
            onShare: () async {
              if (!_isPremium) {
                InterstitialService.show();
              }
              try {
                final cacheDir = await getTemporaryDirectory();
                final tempDir = Directory("${cacheDir.path}/share_single");

                if (!await tempDir.exists()) {
                  await tempDir.create(recursive: true);
                }

                final fileName = fileMap['name'] as String;
                final tempPath = "${tempDir.path}/$fileName";

                final bytes = await platform.invokeMethod('readFileBytes', {'uri': uri});
                if (bytes != null) {
                  final tempFile = File(tempPath);
                  await tempFile.writeAsBytes(bytes);
                  await Share.shareXFiles([XFile(tempPath)]);
                }
              } catch (e) {
                print('Error sharing: $e');
              }
            },
            loadImageBytes: _loadImageBytes,
            getVideoFilePath: _getVideoFilePath,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (showPermissionScreen && !isLoading && savedFolderUri == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text("Status Bank",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal, Color(0xFF05615B)],
                begin: Alignment.centerLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 80, color: Colors.teal),
                SizedBox(height: 24),
                Text(
                  'Access Required',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Text(
                  'Please grant access to WhatsApp status folder',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _requestStoragePermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  child: Text('Grant Access', style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isDark ? Color(0xFF121212) : Colors.white,
        appBar: AppBar(
            leading: selectionMode
                ? IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: deselectAll,
            )
                : null,
            title: selectionMode
                ? Text("${selectedPaths.length} Selected",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600))
                : Text("Status Bank",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [Colors.teal, Color(0xFF05615B)],
                    begin: Alignment.centerLeft,
                    end: Alignment.bottomRight),
              ),
            ),
            actions: [
              if (selectionMode) ...[
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white),
                  onPressed: downloadSelectedFiles,
                ),
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: shareSelectedFiles,
                ),
              ] else
                IconButton(
                  icon: Icon(Icons.refresh, color: Colors.white),
                  onPressed: _loadFilesFromSavedUri,
                ),
              IconButton(onPressed: (){
                Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(),));
              }, icon: Icon(Icons.message, color: Colors.white,)),
            ],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(48),
              child: Container(
                color: isDark ? Color(0xFF121212) : Colors.white,
                child: TabBar(
                  indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(width: 3.0, color: Colors.teal)),
                  indicatorColor: Colors.teal,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.teal,
                  unselectedLabelColor: isDark ? Colors.white70 : Colors.black,
                  tabs: [
                    Tab(text: "Images"),
                    Tab(text: "Videos"),
                  ],
                ),
              ),
            )),
        body: TabBarView(children: [
          buildGrid(imageFiles, true),
          buildGrid(videoFiles, false),
        ]),
      ),
    );
  }
}

// ✅ Separate stateful widget for each thumbnail to preserve state independently
class _MediaThumbnail extends StatefulWidget {
  final String uri;
  final bool isVideo;
  final bool isSelected;
  final bool selectionMode;
  final bool isPremium;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  final Future<Uint8List?> Function(String) loadImageBytes;
  final Future<String?> Function(String) getVideoFilePath;

  const _MediaThumbnail({
    required this.uri,
    required this.isVideo,
    required this.isSelected,
    required this.selectionMode,
    required this.isPremium,
    required this.onTap,
    required this.onLongPress,
    required this.onDownload,
    required this.onShare,
    required this.loadImageBytes,
    required this.getVideoFilePath,
  });

  @override
  State<_MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<_MediaThumbnail> with AutomaticKeepAliveClientMixin {
  dynamic _cachedData;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    if (_cachedData != null) return; // Already loaded

    try {
      final data = widget.isVideo
          ? await widget.getVideoFilePath(widget.uri)
          : await widget.loadImageBytes(widget.uri);

      if (mounted) {
        setState(() {
          _cachedData = data;
          _isLoading = false;
          _hasError = data == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: _buildMediaContent(),
          ),
        ),

        // Selection overlay
        if (widget.selectionMode)
          Positioned(
            left: 8,
            top: 8,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Icon(
                widget.isSelected
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),

        // Action buttons
        if (!widget.selectionMode)
          Positioned(
            top: 2,
            right: 2,
            child: Column(
              children: [
                IconButton(
                  onPressed: widget.onDownload,
                  icon: const Icon(Icons.download, color: Colors.white),
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.black45),
                ),
                IconButton(
                  onPressed: widget.onShare,
                  icon: const Icon(Icons.share, color: Colors.white),
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.black45),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMediaContent() {
    if (_isLoading) {
      return Container(
        height: double.infinity,
        width: double.infinity,
        color: Colors.grey[300],
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
          ),
        ),
      );
    }

    if (_hasError || _cachedData == null) {
      return Container(
        height: double.infinity,
        width: double.infinity,
        color: Colors.grey[300],
        child: Icon(
          widget.isVideo ? Icons.videocam_off : Icons.broken_image,
          size: 40,
          color: Colors.grey[600],
        ),
      );
    }

    if (widget.isVideo) {
      return VideoPreview(videoPath: _cachedData as String);
    }

    return Image.memory(
      _cachedData as Uint8List,
      fit: BoxFit.cover,
      height: double.infinity,
      width: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[300],
          child: Icon(
            Icons.broken_image,
            size: 40,
            color: Colors.grey[600],
          ),
        );
      },
    );
  }
}