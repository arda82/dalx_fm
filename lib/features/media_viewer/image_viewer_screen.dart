// features/media_viewer/image_viewer_screen.dart
//
// Fase 3 — Media Viewer: image viewer full-screen.
// Dibuka dari explorer_screen.dart saat tap file gambar (bukan
// folder). Terima daftar SEMUA gambar di folder yang sedang dibuka
// (bukan cuma satu file) supaya user bisa swipe kiri/kanan pindah
// antar gambar tanpa keluar-masuk viewer.
//
// Modul ini TIDAK memanggil file_engine atau explorer_ui langsung —
// cuma terima data lewat constructor (List<FileItem> + initialIndex),
// sesuai aturan modular di ARCHITECTURE.md bagian 3. Kalau nanti
// butuh refresh isi folder dari sini, itu lewat Event System, bukan
// panggilan langsung.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../../core/models/file_item.dart';

const _dalxAccent = Color(0xFF0A84FF);

class ImageViewerScreen extends StatefulWidget {
  final List<FileItem> images;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.images[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _chromeVisible
          ? AppBar(
              backgroundColor: Colors.black.withOpacity(0.4),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Text(
                currentItem.name,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          : null,
      body: GestureDetector(
        onTap: _toggleChrome,
        child: PhotoViewGallery.builder(
          pageController: _pageController,
          itemCount: widget.images.length,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          builder: (context, index) {
            final item = widget.images[index];
            return PhotoViewGalleryPageOptions(
              imageProvider: FileImage(File(item.path)),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              heroAttributes: PhotoViewHeroAttributes(tag: item.path),
            );
          },
          loadingBuilder: (context, event) => const Center(
            child: CircularProgressIndicator(color: _dalxAccent),
          ),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
        ),
      ),
      bottomNavigationBar: _chromeVisible && widget.images.length > 1
          ? Container(
              color: Colors.black.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '${_currentIndex + 1} / ${widget.images.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            )
          : null,
    );
  }
}
