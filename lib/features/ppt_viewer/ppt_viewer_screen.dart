// features/ppt_viewer/ppt_viewer_screen.dart
//
// Fase 8 Pilar #1 — Preview PPT. PREVIEW DOANG, tidak ada edit sama
// sekali (lihat ARCHITECTURE.md bagian 7.2). Render manual pakai
// Flutter widgets dari hasil parse pptx_parser.dart — BUKAN render
// native/akurat 100% terhadap PowerPoint asli, cuma "gambaran isi"
// (teks + gambar + posisi/ukuran relatif). Shape kompleks (chart,
// table, SmartArt, animasi) tidak didukung, lihat catatan scope di
// pptx_parser.dart.

import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'pptx_parser.dart';

/// Dijalankan di isolate terpisah lewat [compute] — parsing XML file
/// .pptx besar (banyak slide/gambar resolusi tinggi) bisa berat,
/// TIDAK boleh blocking UI thread.
PptDocument _parseInIsolate(Uint8List bytes) => PptxParser.parse(bytes);

class PptViewerScreen extends StatefulWidget {
  final String path;
  const PptViewerScreen({super.key, required this.path});

  @override
  State<PptViewerScreen> createState() => _PptViewerScreenState();
}

class _PptViewerScreenState extends State<PptViewerScreen> {
  late Future<PptDocument> _future;
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PptDocument> _load() async {
    final bytes = await File(widget.path).readAsBytes();
    return compute(_parseInIsolate, bytes);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _fileName {
    final parts = widget.path.split('/');
    return parts.isEmpty ? widget.path : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_fileName, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<PptDocument>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is PptxParseException
                ? (snapshot.error as PptxParseException).message
                : 'Gagal membuka file presentasi ini.';
            return _ErrorState(message: message);
          }

          final doc = snapshot.data!;
          if (doc.slides.isEmpty) {
            return const _ErrorState(message: 'Tidak ada slide yang bisa ditampilkan.');
          }

          return Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: doc.slides.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, index) => _SlideView(
                    slide: doc.slides[index],
                    aspectRatio: doc.aspectRatio,
                  ),
                ),
              ),
              Container(
                color: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                child: Text(
                  'Slide ${_currentPage + 1} / ${doc.slides.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final PptSlide slide;
  final double aspectRatio;
  const _SlideView({required this.slide, required this.aspectRatio});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Container(
            color: Colors.white,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return Stack(
                  children: slide.shapes.map((shape) {
                    return Positioned(
                      left: shape.xFraction * w,
                      top: shape.yFraction * h,
                      width: shape.wFraction * w,
                      height: shape.hFraction * h,
                      child: shape.imageBytes != null
                          ? Image.memory(shape.imageBytes!, fit: BoxFit.contain)
                          : _SlideText(text: shape.text ?? ''),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SlideText extends StatelessWidget {
  final String text;
  const _SlideText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: Text(
          text,
          style: const TextStyle(color: Colors.black87, fontSize: 24),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.slideshow, size: 48, color: Colors.white38),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
