// features/media_viewer/video_viewer_screen.dart
//
// Fase 3 — Media Viewer: video player sederhana.
// Sengaja pakai video_player polos (bukan chewie) supaya UI kontrol
// konsisten warna aksen DalX (#0A84FF) tanpa perlu override skin
// package lain — sejalan dengan filosofi "Function First, kecil &
// ringan" di ARCHITECTURE.md.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

const _dalxAccent = Color(0xFF0A84FF);

class VideoViewerScreen extends StatefulWidget {
  final String path;
  final String? title;

  const VideoViewerScreen({super.key, required this.path, this.title});

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late final VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _isInitialized = true);
        _controller.play();
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _hasError = true);
      });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  void _toggleControls() => setState(() => _controlsVisible = !_controlsVisible);

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.title ?? widget.path.split('/').last;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          fileName,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _hasError
          ? const Center(
              child: Text(
                'Video tidak bisa diputar (format tidak didukung).',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            )
          : !_isInitialized
              ? const Center(child: CircularProgressIndicator(color: _dalxAccent))
              : GestureDetector(
                  onTap: _toggleControls,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                        if (_controlsVisible)
                          IconButton(
                            iconSize: 56,
                            color: Colors.white,
                            icon: Icon(
                              _controller.value.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                            ),
                            onPressed: _togglePlay,
                          ),
                        if (_controlsVisible)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _buildBottomControls(),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildBottomControls() {
    final position = _controller.value.position;
    final duration = _controller.value.duration;

    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text(_formatDuration(position), style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _dalxAccent,
                thumbColor: _dalxAccent,
                inactiveTrackColor: Colors.white24,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: position.inMilliseconds
                    .clamp(0, duration.inMilliseconds)
                    .toDouble(),
                max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1,
                onChanged: (value) {
                  _controller.seekTo(Duration(milliseconds: value.toInt()));
                },
              ),
            ),
          ),
          Text(_formatDuration(duration), style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
