import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:status_bank/video_preview.dart';
import 'package:status_bank/widget.dart';

import 'chat_screen.dart';
import 'full_screen_status.dart';
import 'interstitial_ad_service.dart';


class StatusTabPage extends StatefulWidget {
  final String title;
  const StatusTabPage({super.key, required this.title});

  @override
  State<StatusTabPage> createState() => _StatusTabPageState();
}

class _StatusTabPageState extends State<StatusTabPage>
    with SingleTickerProviderStateMixin {
  final List<String> whatsappStatusPath = [
    "/storage/emulated/Whatsapp/Media/.Statuses",
    "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses", ];

  List<FileSystemEntity> imageFiles = [];
  List<FileSystemEntity> videoFile = [];

  @override
  void initState() {
    super.initState();
    requestAndPermission();
  }
  Future<void> requestAndPermission() async {
    var status = await Permission.storage.status;
    if(!status.isGranted){
      await Permission.storage.request();
    }
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
    await fetchStatuses();

  }

  Future<void> fetchStatuses () async {
    List<FileSystemEntity> image = [];
    List<FileSystemEntity> video = [];

    for(String path in whatsappStatusPath){
      final directory = Directory(path);
      if( await directory.exists()) {
        final allFiles = directory.listSync();
        image.addAll(allFiles.where((file) =>
        file.path.endsWith(".jpg") || file.path.endsWith(".png")));
        video.addAll(allFiles.where((file) =>
        file.path.endsWith(".mp4") || file.path.endsWith(".3gp")));
      }
    }
    setState(() {
      imageFiles=image;
      videoFile=video;
    });
  }

  Future<void> saveFile(File file) async {
    final dir = Directory("/storage/emulated/0/StatusSaver");

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final savedPath = "${dir.path}/${p.basename(file.path)}";
    await file.copy(savedPath);

    showCustomOverlay(context, "File Saved Successfully");
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
        crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = File(files[index].path);

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullScreenStatus(
                  allFiles: files.map((f) => f.path).toList(), // pass all files
                  initialIndex: index, // start at tapped one
                ),
              ),
            );
          },
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 4,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: isImage
                      ? Image.file(file,
                      fit: BoxFit.cover,
                      height: double.infinity,
                      width: double.infinity)
                      :  VideoPreview(videoPath: file.path),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Column(
                    children: [
                      IconButton(
                        onPressed: () {
                          InterstitialService.show();
                           saveFile(file);},
                        icon: const Icon(Icons.download, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black38,
                        ),
                      ),
                      IconButton(
                        onPressed: (){
                          InterstitialService.show();
                          Share.shareXFiles([XFile(file.path)]);},
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
        backgroundColor: isDark? Color(0xFF121212): Colors.white,
        appBar: AppBar(
            title: Text("Status Saver",
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
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                    onPressed: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (context) => ChatScreen()));
                    },
                    icon: Icon(
                      Icons.chat_rounded,
                      color: Colors.white,
                    )),
              )
            ],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(48),
              child: Container(
                color: isDark? Color(0xFF121212): Colors.white,
                child: TabBar(
                  indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(width: 3.0, color: Colors.teal)),
                  indicatorColor: Colors.teal,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.teal,
                  unselectedLabelColor: isDark? Colors.white70: Colors.black,
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
