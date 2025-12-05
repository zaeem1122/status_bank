import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:status_bank/widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

class FullScreenStatus2 extends StatefulWidget {
  final List<String> allFiles; // all saved files (images + videos)
  final int initialIndex; // start from tapped file

  const FullScreenStatus2({
    super.key,
    required this.allFiles,
    required this.initialIndex,
  });

  @override
  State<FullScreenStatus2> createState() => _FullScreenStatus2State();
}

class _FullScreenStatus2State extends State<FullScreenStatus2> {
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
        final VideoPlayerController videoController =
        VideoPlayerController.file(File(path));
        videoController.initialize().then((_) {
          videoController.play();
          videoController.setLooping(false);
          setState(() {});
        });
        _videoControllers[index] = videoController;
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

  // ✅ Delete file from saved directory
  Future<void> _deleteFile(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete File", style: TextStyle(color: Colors.black),),
        content: const Text("Are you sure you want to delete this file?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.teal),),
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
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
       showCustomOverlay(context, "File Delete Successfully");
        setState(() {
          widget.allFiles.remove(path);
        });
        if (widget.allFiles.isEmpty) Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error deleting file: $e")),
      );
    }
  }


  // Future<void> repostToWhatsApp(String filePath) async {
  //   final file = XFile(filePath);
  //   await Share.shareXFiles(
  //     [file],
  //     text: "Reposting this status",
  //     subject: "Status",
  //   );
  //
  //   // final uri = Uri.parse("whatsapp://send?text=Reposting%this%status");
  //   //
  //   // if (await canLaunchUrl(uri)) {
  //   //   await launchUrl(uri);
  //   // } else {
  //   //   ScaffoldMessenger.of(context).showSnackBar(
  //   //     const SnackBar(content: Text("WhatsApp not installed")),
  //   //   );
  //   // }
  // }

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
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          colors: const VideoProgressColors(
                            playedColor: Colors.teal,
                            backgroundColor: Colors.grey,
                            bufferedColor: Colors.white70,
                          ),
                        ),
                      ),
                      ValueListenableBuilder(
                        valueListenable: controller,
                        builder: (context, VideoPlayerValue value, _) {
                          final position = value.position;
                          final duration = value.duration;

                          String twoDigits(int n) =>
                              n.toString().padLeft(2, '0');
                          final posText =
                              "${twoDigits(position.inMinutes)}:${twoDigits(position.inSeconds.remainder(60))}";
                          final durText =
                              "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";

                          return Text(
                            "$posText / $durText",
                            style: const TextStyle(color: Colors.white),
                          );
                        },
                      ),
                    ],
                  ),

                  // Action buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // IconButton(
                      //   onPressed: () => repostToWhatsApp(path, context),
                      //   icon: const Icon(Icons.repeat, color: Colors.white),
                      // ),
                      IconButton(
                        onPressed: () async {
                          await Share.shareXFiles([XFile(path)]);
                        },
                        icon: const Icon(Icons.share, color: Colors.white),
                      ),
                      // ✅ Delete button (replaces download)
                      IconButton(
                        onPressed: () async {
                          await _deleteFile(path);
                        },
                        icon: const Icon(Icons.delete, color: Colors.white),
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
      // For images
      return Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
              ),
            ),
          ),
          Container(
            color: Colors.black.withOpacity(0.7),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // IconButton(
                //   onPressed: () => repostToWhatsApp(path,context),
                //   icon: const Icon(Icons.repeat, color: Colors.white),
                // ),
                IconButton(
                  onPressed: () async {
                    await Share.shareXFiles([XFile(path)]);
                  },
                  icon: const Icon(Icons.share, color: Colors.white),
                ),
                // ✅ Delete button
                IconButton(
                  onPressed: () async {
                    await _deleteFile(path);
                  },
                  icon: const Icon(Icons.delete, color: Colors.white,),
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
        title: const Text("Saved Status",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
