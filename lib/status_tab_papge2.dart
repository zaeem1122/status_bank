import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:status_bank/video_preview.dart';
import 'package:status_bank/widget.dart';

import 'chat_screen.dart';
import 'full_screen_status.dart';
import 'interstitial_ad_service.dart';

class StatusTabPage2 extends StatefulWidget {
  final String title;
  const StatusTabPage2({super.key, required this.title});

  @override
  State<StatusTabPage2> createState() => _StatusTabPageState();
}

class _StatusTabPageState extends State<StatusTabPage2>
    with SingleTickerProviderStateMixin {
  final List<String> whatsappStatusPath = [
    "/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses",
    "/storage/emulated/0/WhatsApp Business/Media/.Statuses"
  ];

  List<FileSystemEntity> imageFiles = [];
  List<FileSystemEntity> videoFile = [];

  // ===== VARIABLES FOR MULTI-SELECT =====
  List<String> selectedPaths = [];
  bool selectionMode = false;

  @override
  void initState() {
    super.initState();
    requestAndPermission();
  }

  Future<void> requestAndPermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
    await fetchStatuses();
  }

  Future<void> fetchStatuses() async {
    List<FileSystemEntity> image = [];
    List<FileSystemEntity> video = [];

    for (String path in whatsappStatusPath) {
      final directory = Directory(path);
      if (await directory.exists()) {
        final allFiles = directory.listSync();
        image.addAll(allFiles.where((file) =>
        file.path.endsWith(".jpg") || file.path.endsWith(".png")));
        video.addAll(allFiles.where((file) =>
        file.path.endsWith(".mp4") || file.path.endsWith(".3gp")));
      }
    }
    setState(() {
      imageFiles = image;
      videoFile = video;
    });
  }

  Future<void> saveFile(File file) async {
    final dir = Directory("/storage/emulated/0/StatusSaver");

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final savedPath = "${dir.path}/${p.basename(file.path)}";

    final savedFile = File(savedPath);
    if (await savedFile.exists()) {
      showCustomOverlay(
        context,
        file.path.endsWith(".mp4") || file.path.endsWith(".3gp")
            ? "Video Already Downloaded"
            : "Image Already Downloaded",
      );
      return;
    }
    await file.copy(savedPath);

    showCustomOverlay(context, "File Saved Successfully");
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

  // ===== DESELECT ALL =====
  void deselectAll() {
    setState(() {
      selectedPaths.clear();
      selectionMode = false;
    });
  }

  // ===== DOWNLOAD MULTIPLE FILES =====
  Future<void> downloadSelectedFiles() async {
    if (selectedPaths.isEmpty) return;

    final dir = Directory("/storage/emulated/0/StatusSaver");
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    int savedCount = 0;
    int alreadyExistCount = 0;

    for (var path in selectedPaths) {
      final file = File(path);
      final fileName = p.basename(file.path);
      final savedPath = "${dir.path}/$fileName";
      final savedFile = File(savedPath);

      if (await savedFile.exists()) {
        alreadyExistCount++;
      } else {
        await file.copy(savedPath);
        savedCount++;
      }
    }

    selectedPaths.clear();
    selectionMode = false;
    setState(() {});

    // Show appropriate message
    if (savedCount > 0 && alreadyExistCount > 0) {
      showCustomOverlay(
        context,
        "$savedCount files saved, $alreadyExistCount already existed",
      );
    } else if (savedCount > 0) {
      showCustomOverlay(context, "$savedCount files saved successfully");
    } else if (alreadyExistCount > 0) {
      showCustomOverlay(context, "All selected files already downloaded");
    }
  }

  // ===== SHARE MULTIPLE FILES =====
  Future<void> shareSelectedFiles() async {
    if (selectedPaths.isEmpty) return;

    final xfiles = selectedPaths.map((e) => XFile(e)).toList();
    await Share.shareXFiles(xfiles, text: "Sharing multiple statuses");

    selectedPaths.clear();
    selectionMode = false;
    setState(() {});
  }

  Widget buildGrid(List<FileSystemEntity> files, bool isImage) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isImage ? Icons.image : Icons.video_collection,
                size: 70, color: Colors.teal),
            Text(
              isImage ? "No Image Status Found" : "No Video Status Found",
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
                        builder: (_) => FullScreenStatus(
                          allFiles: files.map((f) => f.path).toList(),
                          initialIndex: index,
                        ),
                      ),
                    );
                  },
                  onLongPress: () {
                    toggleSelect(path);
                  },
                  child: isImage
                      ? Image.file(file,
                      fit: BoxFit.cover,
                      height: double.infinity,
                      width: double.infinity)
                      : VideoPreview(videoPath: file.path),
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

              // ===== HIDE PER-ITEM BUTTONS WHEN SELECTION MODE =====
              if (!selectionMode)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Column(
                    children: [
                      IconButton(
                        onPressed: () {
                          InterstitialService.show();
                          saveFile(file);
                        },
                        icon: const Icon(Icons.download, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black38,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          InterstitialService.show();
                          Share.shareXFiles([XFile(file.path)]);
                        },
                        icon: const Icon(Icons.share, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black38,
                        ),
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
                : Text("Status Saver",
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
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: IconButton(
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => ChatScreen()));
                      },
                      icon: Icon(
                        Icons.chat_rounded,
                        color: Colors.white,
                      )),
                ),
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
                    Tab(
                      text: "Images",
                    ),
                    Tab(
                      text: "Videos",
                    ),
                  ],
                ),
              ),
            )),
        body: TabBarView(children: [
          buildGrid(imageFiles, true),
          buildGrid(videoFile, false),
        ]),
      ),
    );
  }
}