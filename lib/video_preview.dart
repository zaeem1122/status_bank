import 'package:video_player/video_player.dart';
import 'dart:io';
import 'package:flutter/material.dart';

class VideoPreview extends StatefulWidget {
  final String videoPath;
  const VideoPreview({super.key, required this.videoPath});

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  // New method to handle initialization
  void _initializeVideoPlayer() {
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..setVolume(0) // mute
      ..setLooping(true)
      ..initialize().then((_) {
        // Ensure the controller is still initialized and mounted before playing
        if (mounted && _controller.value.isInitialized) {
          setState(() {}); // Trigger rebuild to show the initialized video
          _controller.play(); // autoplay
        }
      }).catchError((error) {
        // Handle potential errors during initialization
        debugPrint("Error initializing video: $error");
        // You might want to show an error state or a placeholder here
      });
  }

  // 💥 NEW: This method is called when the widget's configuration changes
  @override
  void didUpdateWidget(covariant VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoPath != oldWidget.videoPath) {
      // If the video path has changed, dispose the old controller
      // and initialize a new one with the new path.
      _controller.dispose();
      _initializeVideoPlayer(); // Call the new initialization method
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover, // same behavior as Image.file with cover
        child: SizedBox(
          width: _controller.value.size.width,
          height: _controller.value.size.height,
          child: VideoPlayer(_controller),
        ),
      ),
    )
        : const Center(child: CircularProgressIndicator()); // Or an error icon
  }
}