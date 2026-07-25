// features/ppt_viewer/pptx_parser.dart
//
// Parser .pptx MANUAL — bukan pakai package Flutter siap pakai
// (belum ada yang matang untuk ini, lihat ARCHITECTURE.md bagian 7.2
// Fase 8 Pilar #1). .pptx itu ZIP berisi banyak file XML; di sini
// kita baca lewat package:archive (sudah dipakai di Fase 5), lalu
// parse XML-nya lewat package:xml (BARU, perlu ditambah manual ke
// pubspec.yaml: `xml: ^6.5.0`).
//
// SCOPE SENGAJA DIBATASI (preview doang, bukan replika visual
// sempurna — lihat ARCHITECTURE.md):
// - Teks: digabung per shape (semua paragraf & run jadi satu blok),
//   TANPA styling detail (bold/italic/warna/ukuran font per-run
//   diabaikan, dianggap di luar scope "preview").
// - Gambar: diekstrak sebagai bytes, ditempatkan sesuai posisi &
//   ukuran relatif shape-nya.
// - Shape lain (chart, table, SmartArt, video, animasi) TIDAK
//   didukung — akan dilewati begitu saja (bukan error), jadi slide
//   yang isinya shape-shape itu bakal tampil kosong/parsial di
//   preview. Ini keterbatasan yang disadari, bukan bug.
// - Posisi/ukuran dihitung relatif (fraction 0.0-1.0 terhadap ukuran
//   slide), BUKAN pixel absolut — supaya UI bisa scale ke ukuran
//   layar berapa pun (lihat ppt_viewer_screen.dart, dibungkus
//   AspectRatio sesuai rasio slide asli).
// - Shape yang posisinya diwarisi dari layout/master (placeholder
//   tanpa <a:xfrm> eksplisit di slide-nya sendiri) DILEWATI, tidak
//   dicoba resolve ke layout/master — di luar scope preview.

import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Satu slide hasil parsing — daftar shape (teks atau gambar) dengan
/// posisi & ukuran relatif terhadap slide.
class PptSlide {
  final List<PptShape> shapes;
  const PptSlide(this.shapes);
}

/// Satu shape di slide. Cuma salah satu dari [text]/[imageBytes] yang
/// terisi (bukan dua-duanya) — [text] null berarti ini gambar,
/// [imageBytes] null berarti ini teks.
class PptShape {
  final double xFraction;
  final double yFraction;
  final double wFraction;
  final double hFraction;
  final String? text;
  final Uint8List? imageBytes;

  const PptShape({
    required this.xFraction,
    required this.yFraction,
    required this.wFraction,
    required this.hFraction,
    this.text,
    this.imageBytes,
  });
}

/// Hasil parsing lengkap satu file .pptx: daftar slide + rasio aspek
/// slide asli (dari presentation.xml, fallback 16:9 kalau tidak ada/
/// gagal dibaca).
class PptDocument {
  final List<PptSlide> slides;
  final double aspectRatio;
  const PptDocument({required this.slides, required this.aspectRatio});
}

class PptxParseException implements Exception {
  final String message;
  const PptxParseException(this.message);
  @override
  String toString() => 'PptxParseException: $message';
}

class PptxParser {
  static double _slideExtentCx = 0;
  static double _slideExtentCy = 0;

  /// Parse file .pptx dari [bytes]. Melempar [PptxParseException]
  /// kalau file bukan ZIP valid / struktur inti (presentation.xml,
  /// daftar slide) tidak ditemukan sama sekali. Kegagalan PARSIAL di
  /// level slide/shape individual TIDAK melempar exception — slide
  /// itu cuma jadi kosong/parsial (lihat catatan scope di atas),
  /// supaya satu slide rusak tidak menggagalkan seluruh dokumen.
  static PptDocument parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw const PptxParseException('File bukan .pptx valid (gagal dibuka sebagai ZIP)');
    }

    final filesByName = <String, ArchiveFile>{
      for (final f in archive.files)
        if (f.isFile) f.name: f,
    };

    String? readXmlString(String path) {
      final file = filesByName[path];
      if (file == null) return null;
      return String.fromCharCodes(file.content as List<int>);
    }

    final presentationXml = readXmlString('ppt/presentation.xml');
    if (presentationXml == null) {
      throw const PptxParseException('ppt/presentation.xml tidak ditemukan — bukan .pptx valid');
    }

    final aspectRatio = _parseAspectRatioAndSetExtent(presentationXml);
    final slideOrderRIds = _parseSlideOrderRIds(presentationXml);

    final presRelsXml = readXmlString('ppt/_rels/presentation.xml.rels');
    final ridToTarget = presRelsXml == null ? <String, String>{} : _parseRelationships(presRelsXml);

    // Urutan slide FINAL: ikuti sldIdLst di presentation.xml (urutan
    // asli sesuai PowerPoint), di-resolve ke path file lewat rels.
    // Kalau resolusi ini gagal total (rIds kosong/rels tidak ketemu),
    // fallback ke urutan nama file "slideN.xml" — biasanya (bukan
    // selalu) tetap sesuai urutan asli.
    List<String> slidePaths = slideOrderRIds
        .map((rId) => ridToTarget[rId])
        .whereType<String>()
        .map((target) => _normalizePptPath('ppt/$target'))
        .toList();

    if (slidePaths.isEmpty) {
      final slideFiles = filesByName.keys
          .where((name) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(name))
          .toList();
      slideFiles.sort((a, b) {
        final na = int.parse(RegExp(r'\d+').firstMatch(a)!.group(0)!);
        final nb = int.parse(RegExp(r'\d+').firstMatch(b)!.group(0)!);
        return na.compareTo(nb);
      });
      slidePaths = slideFiles;
    }

    final slides = <PptSlide>[];
    for (final slidePath in slidePaths) {
      try {
        final slide = _parseSlide(slidePath, filesByName, readXmlString);
        slides.add(slide);
      } catch (e) {
        // Satu slide gagal parse -> jangan gagalkan seluruh dokumen,
        // tampil kosong aja (lebih baik daripada preview tidak bisa
        // dibuka sama sekali gara-gara 1 slide bermasalah).
        slides.add(const PptSlide([]));
      }
    }

    if (slides.isEmpty) {
      throw const PptxParseException('Tidak ada slide yang bisa dibaca dari file ini');
    }

    return PptDocument(slides: slides, aspectRatio: aspectRatio);
  }

  static double _parseAspectRatioAndSetExtent(String presentationXml) {
    try {
      final doc = XmlDocument.parse(presentationXml);
      final sldSz = doc.findAllElements('p:sldSz').firstOrNull;
      if (sldSz == null) {
        _slideExtentCx = 12192000;
        _slideExtentCy = 6858000;
        return 16 / 9;
      }
      final cx = double.tryParse(sldSz.getAttribute('cx') ?? '');
      final cy = double.tryParse(sldSz.getAttribute('cy') ?? '');
      if (cx == null || cy == null || cy == 0) {
        _slideExtentCx = 12192000;
        _slideExtentCy = 6858000;
        return 16 / 9;
      }
      _slideExtentCx = cx;
      _slideExtentCy = cy;
      return cx / cy;
    } catch (e) {
      _slideExtentCx = 12192000;
      _slideExtentCy = 6858000;
      return 16 / 9;
    }
  }

  /// Ambil daftar r:id dari <p:sldIdLst><p:sldId r:id="..."/></p:sldIdLst>
  /// — urutan elemen di sini = urutan slide asli di presentasi.
  static List<String> _parseSlideOrderRIds(String presentationXml) {
    try {
      final doc = XmlDocument.parse(presentationXml);
      final sldIdLst = doc.findAllElements('p:sldIdLst').firstOrNull;
      if (sldIdLst == null) return [];
      return sldIdLst
          .findElements('p:sldId')
          .map((e) => e.getAttribute('r:id'))
          .whereType<String>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Parse file .rels (format umum dipakai di beberapa tempat: rels
  /// presentation, DAN rels per-slide untuk resolve gambar).
  static Map<String, String> _parseRelationships(String relsXml) {
    final result = <String, String>{};
    try {
      final doc = XmlDocument.parse(relsXml);
      for (final rel in doc.findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id != null && target != null) result[id] = target;
      }
    } catch (e) {
      // Return apa yang berhasil ke-parse sejauh ini.
    }
    return result;
  }

  /// Normalisasi path relatif ala .pptx (mis. "../media/image1.png"
  /// dari base "ppt/slides") ke path absolut dalam ZIP.
  static String _normalizePptPath(String path) {
    final parts = <String>[];
    for (final segment in path.split('/')) {
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (segment != '.' && segment.isNotEmpty) {
        parts.add(segment);
      }
    }
    return parts.join('/');
  }

  static PptSlide _parseSlide(
    String slidePath,
    Map<String, ArchiveFile> filesByName,
    String? Function(String) readXmlString,
  ) {
    final slideXml = readXmlString(slidePath);
    if (slideXml == null) return const PptSlide([]);

    // Rels punya slide ini sendiri (buat resolve r:embed gambar),
    // lokasinya di folder _rels sebelah file slide-nya.
    final slideDir = slidePath.substring(0, slidePath.lastIndexOf('/'));
    final slideFileName = slidePath.substring(slidePath.lastIndexOf('/') + 1);
    final slideRelsPath = '$slideDir/_rels/$slideFileName.rels';
    final slideRelsXml = readXmlString(slideRelsPath);
    final slideRIdToTarget = slideRelsXml == null ? <String, String>{} : _parseRelationships(slideRelsXml);

    final doc = XmlDocument.parse(slideXml);
    final spTree = doc.findAllElements('p:spTree').firstOrNull;
    if (spTree == null) return const PptSlide([]);

    final shapes = <PptShape>[];

    for (final node in spTree.childElements) {
      if (node.name.local == 'sp') {
        final shape = _parseTextShape(node);
        if (shape != null) shapes.add(shape);
      } else if (node.name.local == 'pic') {
        final shape = _parsePictureShape(node, slideDir, slideRIdToTarget, filesByName);
        if (shape != null) shapes.add(shape);
      }
      // Shape lain (graphicFrame/chart/table, grpSp/group, cxnSp)
      // SENGAJA dilewati — di luar scope preview (lihat header file).
    }

    return PptSlide(shapes);
  }

  static PptShape? _parseTextShape(XmlElement sp) {
    final geometry = _parseGeometry(sp);
    if (geometry == null) return null;

    final txBody = sp.findElements('p:txBody').firstOrNull;
    if (txBody == null) return null;

    final buffer = StringBuffer();
    for (final para in txBody.findElements('a:p')) {
      final runsText = para
          .findElements('a:r')
          .map((r) => r.findElements('a:t').firstOrNull?.innerText ?? '')
          .join();
      if (runsText.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(runsText);
    }

    final text = buffer.toString();
    if (text.trim().isEmpty) return null;

    return PptShape(
      xFraction: geometry.$1,
      yFraction: geometry.$2,
      wFraction: geometry.$3,
      hFraction: geometry.$4,
      text: text,
    );
  }

  static PptShape? _parsePictureShape(
    XmlElement pic,
    String slideDir,
    Map<String, String> slideRIdToTarget,
    Map<String, ArchiveFile> filesByName,
  ) {
    final geometry = _parseGeometry(pic);
    if (geometry == null) return null;

    final blip = pic.findAllElements('a:blip').firstOrNull;
    final embedRId = blip?.getAttribute('r:embed');
    if (embedRId == null) return null;

    final target = slideRIdToTarget[embedRId];
    if (target == null) return null;

    final imagePath = _normalizePptPath('$slideDir/$target');
    final imageFile = filesByName[imagePath];
    if (imageFile == null) return null;

    final bytes = Uint8List.fromList(imageFile.content as List<int>);

    return PptShape(
      xFraction: geometry.$1,
      yFraction: geometry.$2,
      wFraction: geometry.$3,
      hFraction: geometry.$4,
      imageBytes: bytes,
    );
  }

  /// Baca <p:spPr><a:xfrm><a:off x=".." y=".."/><a:ext cx=".." cy=".."/>
  /// dari shape (sp/pic), return fraction relatif ke slide (dibagi
  /// [_slideExtentCx]/[_slideExtentCy] yang di-set sekali di awal
  /// [parse] lewat [_parseAspectRatioAndSetExtent]). Kalau shape
  /// tidak punya posisi eksplisit (placeholder yang mewarisi dari
  /// layout/master — umum terjadi di title/content placeholder),
  /// shape ini dilewati (return null) — TIDAK mencoba resolve ke
  /// layout/master, di luar scope preview.
  static (double, double, double, double)? _parseGeometry(XmlElement shapeNode) {
    final xfrm = shapeNode.findAllElements('a:xfrm').firstOrNull;
    if (xfrm == null) return null;
    final off = xfrm.findElements('a:off').firstOrNull;
    final ext = xfrm.findElements('a:ext').firstOrNull;
    if (off == null || ext == null) return null;

    final x = double.tryParse(off.getAttribute('x') ?? '');
    final y = double.tryParse(off.getAttribute('y') ?? '');
    final cx = double.tryParse(ext.getAttribute('cx') ?? '');
    final cy = double.tryParse(ext.getAttribute('cy') ?? '');
    if (x == null || y == null || cx == null || cy == null) return null;
    if (_slideExtentCx == 0 || _slideExtentCy == 0) return null;

    return (
      x / _slideExtentCx,
      y / _slideExtentCy,
      cx / _slideExtentCx,
      cy / _slideExtentCy,
    );
  }
}

extension on XmlElement {
  String get innerText => children.whereType<XmlText>().map((t) => t.value).join();
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
