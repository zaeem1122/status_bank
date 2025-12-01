import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';
import 'package:status_bank/video_preview.dart';
import 'package:status_bank/widget.dart';

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

  // 🔹 Load all saved files (images + videos)
  Future<void> _loadSavedFiles() async {
    final directory = Directory("/storage/emulated/0/StatusSaver");

    if (await directory.exists()) {
      try {
        final files = directory.listSync();
        files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
        setState(() {
          savedFiles = files;
        });
      } catch (e) {
        debugPrint("Error loading files: $e");
        setState(() => savedFiles = []);
      }
    } else {
      await directory.create(recursive: true);
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
      showCustomOverlay(context, "File Delete Successfully");
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
              Navigator.pop(ctx, true);},
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

  // ===== NEW: SHARE MULTIPLE FILES =====
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
      appBar: AppBar(
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
              onPressed:
                shareSelectedFiles,
            ),
            IconButton(
              icon: const Icon(
                Icons.delete,
                color: Colors.white,
              ),
              onPressed:
                deleteSelectedFiles,
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
                          Share.shareXFiles([XFile(path)]);},
                        icon: const Icon(Icons.share, color: Colors.white),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black45),
                      ),
                      IconButton(
                        onPressed: () {
                          _deleteFile(file);},
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
