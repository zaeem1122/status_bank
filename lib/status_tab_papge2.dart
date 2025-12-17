import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_bank/chat_screen.dart';
import 'package:status_bank/video_preview.dart';
import 'package:status_bank/widget.dart';

import 'full_screen_status.dart';
import 'interstitial_ad_service.dart';

class StatusTabPage2 extends StatefulWidget {
  final String title;
  const StatusTabPage2({super.key, required this.title});

  @override
  State<StatusTabPage2> createState() => _StatusTabPage2State();
}

class _StatusTabPage2State extends State<StatusTabPage2>
    with SingleTickerProviderStateMixin {
  static const platform = MethodChannel('com.yourapp/status_access');

  // ✅ Use app-specific directory
  String? _saveDirPath;

  List<Map<String, dynamic>> imageFiles = [];
  List<Map<String, dynamic>> videoFiles = [];

  String? savedFolderUri;
  bool isLoading = true; // ✅ Start with loading state
  bool showPermissionScreen = false;

  // Multi-select variables
  List<String> selectedPaths = [];
  bool selectionMode = false;

  @override
  void initState() {
    super.initState();
    _initializeSaveDirectory();
    _checkInitialState();
  }

  // ✅ Initialize save directory (same as StatusTabPage)
  Future<void> _initializeSaveDirectory() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _getAndroidVersion();

        if (androidInfo >= 30) {
          // Android 10+ (API 29+): Use app-specific external directory
          final dir = await getExternalStorageDirectory();
          if (dir != null) {
            // Create Business subfolder in StatusSaver
            final saveDir = Directory('${dir.path}/StatusSaver/Business');
            if (!await saveDir.exists()) {
              await saveDir.create(recursive: true);
            }
            _saveDirPath = saveDir.path;
            print('📁 Business save directory: $_saveDirPath');
          }
        } else {
          // Android 9 and below: Use public directory
          _saveDirPath = "/storage/emulated/0/StatusSaver/Business";
        }
      }
    } catch (e) {
      print('❌ Error initializing save directory: $e');
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        _saveDirPath = '${dir.path}/StatusSaver/Business';
      }
    }
  }

  Future<void> _checkInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    // DIFFERENT KEY for Business WhatsApp
    savedFolderUri = prefs.getString('status_folder_uri_business');

    if (savedFolderUri != null) {
      await _loadFilesFromSavedUri();
    } else {
      setState(() {
        showPermissionScreen = true;
        isLoading = false; // ✅ Stop loading when showing permission screen
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

      // CALLS BUSINESS WHATSAPP FUNCTION
      final String? folderUri = await platform.invokeMethod('openBusinessStatusFolderPicker');

      if (folderUri != null && folderUri.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        // SAVE WITH DIFFERENT KEY
        await prefs.setString('status_folder_uri_business', folderUri);
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
          {'uri': savedFolderUri, 'isBusiness': 'true'}  // BUSINESS WHATSAPP
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
      _showErrorDialog('Could not find status files.\n\nMake sure you selected the "com.whatsapp.w4b" folder.');
    }
  }

  Future<Uint8List?> _loadImageBytes(String uriString) async {
    try {
      final bytes = await platform.invokeMethod('readFileBytes', {'uri': uriString});
      return bytes as Uint8List?;
    } catch (e) {
      print('Error loading image: $e');
      return null;
    }
  }

  Future<String?> _getVideoFilePath(String uriString) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final videoDir = Directory("${cacheDir.path}/video_previews_business");

      if (!await videoDir.exists()) {
        await videoDir.create(recursive: true);
      }

      final fileName = uriString.split('/').last.split('?').first;
      final localPath = "${videoDir.path}/$fileName";
      final localFile = File(localPath);

      if (await localFile.exists()) {
        return localPath;
      }

      final bytes = await platform.invokeMethod('readFileBytes', {'uri': uriString});
      if (bytes != null) {
        await localFile.writeAsBytes(bytes);
        return localPath;
      }

      return null;
    } catch (e) {
      print('Error getting video file path: $e');
      return null;
    }
  }

  // ✅ Save single file (same as StatusTabPage)
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

      // Verify file was written
      if (await savedFile.exists()) {
        final fileSize = await savedFile.length();
        print('✅ File saved successfully: $savedPath (${fileSize} bytes)');
        showCustomOverlay(context, "Saved to StatusSaver/Business folder");
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

  // ✅ Download multiple selected files (same as StatusTabPage)
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

              // Verify file was saved
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

      // Show appropriate message
      if (savedCount > 0 && alreadyExistCount > 0) {
        showCustomOverlay(context, "$savedCount saved, $alreadyExistCount already existed");
      } else if (savedCount > 0) {
        showCustomOverlay(context, "$savedCount files saved to StatusSaver/Business");
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
    final tempDir = Directory("${cacheDir.path}/share_temp_business");

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

  // ✅ Full screen view (same as StatusTabPage)
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

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 4,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    if (selectionMode) {
                      toggleSelect(uri);
                      return;
                    }
                    _openFullScreen(index, files);
                  },
                  onLongPress: () {
                    toggleSelect(uri);
                  },
                  child: FutureBuilder<dynamic>(
                    future: isVideo ? _getVideoFilePath(uri) : _loadImageBytes(uri),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
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

                      if (!snapshot.hasData || snapshot.data == null) {
                        return Container(
                          height: double.infinity,
                          width: double.infinity,
                          color: Colors.grey[300],
                          child: Icon(
                            isVideo ? Icons.videocam_off : Icons.broken_image,
                            size: 40,
                            color: Colors.grey[600],
                          ),
                        );
                      }

                      // ✅ Use VideoPreview for videos (same as StatusTabPage)
                      if (isVideo) {
                        return VideoPreview(videoPath: snapshot.data as String);
                      }

                      // Use Image.memory for images
                      return Image.memory(
                        snapshot.data as Uint8List,
                        fit: BoxFit.cover,
                        height: double.infinity,
                        width: double.infinity,
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
                    },
                  ),
                ),
              ),

              // ===== SELECTION OVERLAY =====
              if (selectionMode)
                Positioned(
                  left: 8,
                  top: 8,
                  child: GestureDetector(
                    onTap: () => toggleSelect(uri),
                    child: Icon(
                      selectedPaths.contains(uri)
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),

              // ===== HIDE PER-ITEM DOWNLOAD/SHARE WHEN SELECTION MODE =====
              if (!selectionMode)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Column(
                    children: [
                      IconButton(
                        onPressed: () {
                          InterstitialService.show();
                          saveFile(fileMap);
                        },
                        icon: const Icon(Icons.download, color: Colors.white),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black45),
                      ),
                      IconButton(
                        onPressed: () async {
                          InterstitialService.show();
                          try {
                            final cacheDir = await getTemporaryDirectory();
                            final tempDir = Directory("${cacheDir.path}/share_single_business");

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
                        icon: const Icon(Icons.share, color: Colors.white),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black45),
                      ),
                    ],
                  ),
                ),
            ],
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
                Icon(Icons.business, size: 80, color: Colors.teal),
                SizedBox(height: 24),
                Text(
                  'Access Required',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Text(
                  'Please grant access to WhatsApp Business status folder',
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
