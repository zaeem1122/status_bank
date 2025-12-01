import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:status_bank/widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'interstitial_ad_service.dart';


class FullScreenStatus extends StatefulWidget {
  final List<String> allFiles;
  final int initialIndex;

  const FullScreenStatus({
    super.key,
    required this.allFiles,
    required this.initialIndex,
  });

  @override
  State<FullScreenStatus> createState() => _FullScreenStatusState();
}

class _FullScreenStatusState extends State<FullScreenStatus> {
  late PageController _pageController;
  int currentIndex = 0;

  final Map<int, VideoPlayerController> _videoControllers = {};

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _initController(currentIndex);
  }

  void _initController(int index) {
    final path = widget.allFiles[index];
    if (path.endsWith(".mp4") || path.endsWith(".3gp")) {
      if (!_videoControllers.containsKey(index)) {
        final controller = VideoPlayerController.file(File(path));
        controller.initialize().then((_) {
          controller.play();
          controller.setLooping(false);
          setState(() {});
        });
        _videoControllers[index] = controller;
      }
    }
  }

  @override
  void dispose() {
    for (var c in _videoControllers.values) {
      c.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  // ✅ Save file to app directory
  Future<void> saveFile(File file) async {
    final dir = Directory("/storage/emulated/0/StatusSaver");

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final savedPath = "${dir.path}/${p.basename(file.path)}";
    await file.copy(savedPath);

    showCustomOverlay(context, "File Saved Successfully");
  }

  Future<void> repostToWhatsApp(String filePath) async {
    final file = XFile(filePath);
    /*  await Share.shareXFiles(
      [file],
      text: "Reposting this status",
    );
*/
    final uri = Uri.parse("whatsapp://send?text=Reposting%20this%20status");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("WhatsApp not installed")),
      );
    }
  }

  Widget _buildContent(String path, int index) {
    if (path.endsWith(".mp4") || path.endsWith(".3gp")) {
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
                      // IconButton(
                      //   onPressed: () => repostToWhatsApp(path),
                      //   icon: const Icon(Icons.repeat, color: Colors.white),
                      // ),
                      IconButton(
                        onPressed: () {
                          InterstitialService.show();
                          Share.shareXFiles([XFile(path)]);},
                        icon: const Icon(Icons.share, color: Colors.white),
                      ),
                      IconButton(
                        onPressed: ()  {
                           InterstitialService.show();
                        saveFile(File(path));},
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
            child: CircularProgressIndicator(color: Colors.white));
      }
    } else {
      return Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
          ),
          Container(
            color: Colors.black.withOpacity(0.7),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // IconButton(
                //   onPressed: () => repostToWhatsApp(path),
                //   icon: const Icon(Icons.repeat, color: Colors.white),
                // ),
                IconButton(
                  onPressed: () {
                    InterstitialService.show();
                    Share.shareXFiles([XFile(path)]);},
                  icon: const Icon(Icons.share, color: Colors.white),
                ),
                IconButton(
                  onPressed: ()  {
                    InterstitialService.show();
                    saveFile(File(path));},
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
        iconTheme: IconThemeData(color: Colors.white),
        title:
        const Text("Status Saver", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black87,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.allFiles.length,
        onPageChanged: (index) {
          setState(() => currentIndex = index);
          _initController(index);
        },
        itemBuilder: (context, index) {
          return _buildContent(widget.allFiles[index], index);
        },
      ),
    );
  }
}
