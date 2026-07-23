// features/doc_viewer/pdf_viewer_screen.dart
//
// Fase 6 — Doc Viewer bagian PDF. Basic aja: scroll antar halaman +
// pinch zoom, bukan editor. Pakai flutter_pdfview (native PdfRenderer
// Android di baliknya) — bukan pure Dart, karena render PDF berat
// kalau ditulis manual, dan PdfRenderer bawaan Android sudah
// teroptimasi + gratis tanpa lisensi.
//
// AppBar SENGAJA minimal (nama file + indikator halaman "3 / 12"),
// konsisten sama filosofi "Function First" — kontrol pinch-zoom &
// swipe sudah bawaan widget PDFView, tidak perlu tombol tambahan.

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

const _dalxAccent = Color(0xFF0A84FF);

class PdfViewerScreen extends StatefulWidget {
  final String path;

  const PdfViewerScreen({super.key, required this.path});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isReady = false;
  String? _errorMessage;
  PDFViewController? _controller;

  String get _fileName => widget.path.split('/').last;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _fileName,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_isReady && _totalPages > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_currentPage + 1} / $_totalPages',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      body: _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal membuka PDF: $_errorMessage',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Stack(
              children: [
                PDFView(
                  filePath: widget.path,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                  pageSnap: true,
                  defaultPage: _currentPage,
                  fitPolicy: FitPolicy.WIDTH,
                  onRender: (pages) {
                    if (!mounted) return;
                    setState(() {
                      _totalPages = pages ?? 0;
                      _isReady = true;
                    });
                  },
                  onError: (error) {
                    if (!mounted) return;
                    setState(() => _errorMessage = error.toString());
                  },
                  onPageError: (page, error) {
                    if (!mounted) return;
                    setState(() => _errorMessage = 'Halaman $page: $error');
                  },
                  onViewCreated: (controller) {
                    _controller = controller;
                  },
                  onPageChanged: (page, total) {
                    if (!mounted) return;
                    setState(() => _currentPage = page ?? 0);
                  },
                ),
                if (!_isReady)
                  const Center(child: CircularProgressIndicator(color: _dalxAccent)),
              ],
            ),
    );
  }
}
