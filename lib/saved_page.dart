import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';
import 'package:status_bank/video_preview.dart';
import 'package:status_bank/widget.dart';
import 'package:path_provider/path_provider.dart';

import 'full_screen_status2.dart';
import 'interstitial_ad_service.dart';

class SavedPage extends StatefulWidget {
  const SavedPage({super.key});

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<FileSystemEntity> savedFiles = [];

  // ===== VARIABLES FOR MULTI-SELECT =====
  List<String> selectedPaths = [];
  bool selectionMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 🔹 Load all saved files from Gallery directories (Pictures/StatusSaver and Movies/StatusSaver)
  Future<void> _loadSavedFiles() async {
    try {
      Directory picturesDirectory;
      Directory moviesDirectory;

      // Check Android version
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;

        if (androidInfo.version.sdkInt >= 29) {
          // Android 10+ (API 29+): Files are saved to public gallery directories
          // But we can't directly access them, so we need to use app-specific directory
          // OR use MediaStore to query them

          // For now, we'll check both old app-specific AND new public directories
          final externalDir = await getExternalStorageDirectory();

          // Try to access public directories (may not work on all devices)
          picturesDirectory = Directory("/storage/emulated/0/Pictures/StatusSaver");
          moviesDirectory = Directory("/storage/emulated/0/Movies/StatusSaver");

          // If public directories don't exist or are inaccessible, fall back to app directory
          if (!await picturesDirectory.exists() && !await moviesDirectory.exists()) {
            // This means user might be on Android 10+ and we should use MediaStore
            // For simplicity, let's just show a message that files are in Gallery
            debugPrint("Files are saved in Gallery app");
          }
        } else {
          // Android 9 and below: Use public directory
          picturesDirectory = Directory("/storage/emulated/0/Pictures/StatusSaver");
          moviesDirectory = Directory("/storage/emulated/0/Movies/StatusSaver");
        }
      } else {
        // Fallback for non-Android platforms
        picturesDirectory = Directory("/storage/emulated/0/Pictures/StatusSaver");
        moviesDirectory = Directory("/storage/emulated/0/Movies/StatusSaver");
      }

      List<FileSystemEntity> allFiles = [];

      // Load image files from Pictures/StatusSaver
      if (await picturesDirectory.exists()) {
        final pictureFiles = picturesDirectory.listSync();
        allFiles.addAll(pictureFiles.where((entity) => entity is File));
      }

      // Load video files from Movies/StatusSaver
      if (await moviesDirectory.exists()) {
        final movieFiles = moviesDirectory.listSync();
        allFiles.addAll(movieFiles.where((entity) => entity is File));
      }

      // Sort all files by modified date (newest first)
      allFiles.sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );

      setState(() {
        savedFiles = allFiles;
      });
    } catch (e) {
      debugPrint("Error loading files: $e");
      setState(() => savedFiles = []);
    }
  }

  Future<void> _deleteFile(File fileToDelete) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "Delete File",
          style: TextStyle(color: Colors.black),
        ),
        content: const Text("Are you sure you want to delete this file?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.teal),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (await fileToDelete.exists()) {
        await fileToDelete.delete();
      }

      await _loadSavedFiles();
      showCustomOverlay(context, "File Deleted Successfully");
    } catch (e) {
      debugPrint("Error deleting file: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete file: $e")),
      );
    }
  }

  // ===== MULTI-SELECT FUNCTIONS =====
  void toggleSelect(String path) {
    setState(() {
      if (selectedPaths.contains(path)) {
        selectedPaths.remove(path);
        if (selectedPaths.isEmpty) selectionMode = false;
      } else {
        selectedPaths.add(path);
        selectionMode = true;
      }
    });
  }

  // ===== NEW: DESELECT ALL =====
  void deselectAll() {
    setState(() {
      selectedPaths.clear();
      selectionMode = false;
    });
  }

  Future<void> deleteSelectedFiles() async {
    if (selectedPaths.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Selected Files?"),
        content: Text("You are deleting ${selectedPaths.length} files."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.teal),
            ),
          ),
          TextButton(
            onPressed: () {
              InterstitialService.show();
              Navigator.pop(ctx, true);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    for (var path in selectedPaths) {
      final file = File(path);
      if (await file.exists()) file.deleteSync();
    }

    selectedPaths.clear();
    selectionMode = false;

    await _loadSavedFiles();

    showCustomOverlay(context, "Selected files deleted");
  }

  // ===== SHARE MULTIPLE FILES =====
  Future<void> shareSelectedFiles() async {
    if (selectedPaths.isEmpty) return;

    final xfiles = selectedPaths.map((e) => XFile(e)).toList();
    await Share.shareXFiles(xfiles, text: "Sharing multiple statuses");

    selectedPaths.clear();
    selectionMode = false;
    await _loadSavedFiles();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final images = savedFiles.where((file) {
      final mimeType = lookupMimeType(file.path) ?? '';
      return mimeType.startsWith("image/");
    }).toList();

    final videos = savedFiles.where((file) {
      final mimeType = lookupMimeType(file.path) ?? '';
      return mimeType.startsWith("video/");
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
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
            : const Text(
          "Saved Status",
          style:
          TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: dark ? const Color(0xFF121212) : Colors.white,
            child: TabBar(
              controller: _tabController,
              indicator: const UnderlineTabIndicator(
                borderSide: BorderSide(width: 3.0, color: Colors.teal),
              ),
              labelColor: Colors.teal,
              indicatorSize: TabBarIndicatorSize.tab,
              unselectedLabelColor: dark ? Colors.white70 : Colors.black,
              tabs: const [
                Tab(text: "Images"),
                Tab(text: "Videos"),
              ],
            ),
          ),
        ),
        actions: [
          if (selectionMode) ...[
            IconButton(
              icon: const Icon(
                Icons.share,
                color: Colors.white,
              ),
              onPressed: shareSelectedFiles,
            ),
            IconButton(
              icon: const Icon(
                Icons.delete,
                color: Colors.white,
              ),
              onPressed: deleteSelectedFiles,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadSavedFiles,
            ),
          ],
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGrid(images, isVideo: false),
          _buildGrid(videos, isVideo: true),
        ],
      ),
    );
  }

  Widget _buildGrid(List<FileSystemEntity> files, {bool isVideo = false}) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isVideo ? Icons.video_collection : Icons.image,
              size: 70,
              color: Colors.teal,
            ),
            const SizedBox(height: 16),
            Text(
              isVideo ? "No Saved Videos" : "No Saved Images",
              style: const TextStyle(fontSize: 15, color: Colors.teal),
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
      itemBuilder: (context, index) {
        final file = File(files[index].path);
        final path = file.path;

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
                      toggleSelect(path);
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullScreenStatus2(
                          allFiles: files.map((e) => e.path).toList(),
                          initialIndex: index,
                        ),
                      ),
                    ).then((_) => _loadSavedFiles());
                  },
                  onLongPress: () {
                    toggleSelect(path);
                  },
                  child: isVideo
                      ? VideoPreview(videoPath: path)
                      : Image.file(
                    file,
                    fit: BoxFit.cover,
                    height: double.infinity,
                    width: double.infinity,
                  ),
                ),
              ),

              // ===== SELECTION OVERLAY =====
              if (selectionMode)
                Positioned(
                  left: 8,
                  top: 8,
                  child: GestureDetector(
                    onTap: () => toggleSelect(path),
                    child: Icon(
                      selectedPaths.contains(path)
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),

              // ===== HIDE PER-ITEM SHARE/DELETE WHEN SELECTION MODE =====
              if (!selectionMode)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Column(
                    children: [
                      IconButton(
                        onPressed: () {
                          Share.shareXFiles([XFile(path)]);
                        },
                        icon: const Icon(Icons.share, color: Colors.white),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black45),
                      ),
                      IconButton(
                        onPressed: () {
                          _deleteFile(file);
                        },
                        icon: const Icon(Icons.delete, color: Colors.white),
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
}