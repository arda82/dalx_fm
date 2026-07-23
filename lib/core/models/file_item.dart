// core/models/file_item.dart
//
// Model data bersama untuk merepresentasikan satu file/folder.
// Dipakai oleh file_engine (yang membaca dari filesystem) dan
// explorer_ui (yang menampilkannya) — makanya modelnya taruh di
// core/, bukan di salah satu features/.

enum FileItemType { folder, file }

class FileItem {
  final String name;
  final String path;
  final FileItemType type;
  final int sizeBytes;
  final DateTime modifiedAt;

  const FileItem({
    required this.name,
    required this.path,
    required this.type,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  bool get isFolder => type == FileItemType.folder;
  bool get isHidden => name.startsWith('.');

  /// Ekstensi file tanpa titik, huruf kecil. Folder selalu "".
  String get extension {
    if (isFolder) return '';
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  // ---------------- Fase 3: Media Viewer ----------------
  // Dipakai explorer_ui untuk menentukan apakah tap file harus
  // membuka media_viewer (ImageViewerScreen/VideoViewerScreen) atau
  // tetap lewat jalur Open With/Install APK (Fase 1) seperti biasa.

  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  static const _videoExts = {'mp4', 'mkv', 'webm', '3gp', 'mov', 'avi'};

  bool get isImage => !isFolder && _imageExts.contains(extension);
  bool get isVideo => !isFolder && _videoExts.contains(extension);

  // ---------------- Fase 4: Code Editor ----------------
  // Dipakai explorer_ui untuk menentukan apakah tap file harus
  // membuka code_editor (CodeEditorScreen) alih-alih Open With.
  // Daftar ekstensi ini SENGAJA dijaga konsisten manual dengan
  // language_detector.dart di features/code_editor — core/ tidak
  // boleh bergantung pada features/ (lihat ARCHITECTURE.md bagian 3),
  // jadi daftar bahasa yang didukung tidak diimpor dari sana.

  static const _codeExts = {
    'dart', 'py', 'java', 'kt', 'kts', 'c', 'h', 'cpp', 'cc', 'hpp', 'cxx',
    'js', 'ts', 'json', 'yaml', 'yml', 'xml', 'html', 'htm', 'css',
    'md', 'markdown', 'sh', 'bash', 'sql', 'go', 'rs', 'swift', 'php', 'rb',
    'txt', 'log', 'ini', 'cfg', 'gradle', 'properties', 'env',
  };

  bool get isCodeFile => !isFolder && _codeExts.contains(extension);

  // ---------------- Fase 5: Archive ----------------
  // Dipakai explorer_ui buat tentuin kapan "Extract" boleh muncul di
  // menu titik-tiga. Cuma ZIP dulu (pure Dart via package archive) —
  // RAR/7z belum didukung, itu bagian Fase 8 (Native Power-up).

  static const _archiveExts = {'zip'};

  bool get isArchive => !isFolder && _archiveExts.contains(extension);

  // ---------------- Fase 6: Doc Viewer ----------------
  // Dipakai explorer_ui buat tentuin tap file .pdf harus buka
  // PdfViewerScreen, dan tap file .xlsx harus buka XlsxEditorScreen —
  // alih-alih jalur Open With (Fase 1) seperti biasa. .xls (format
  // lama) SENGAJA tidak dimasukkan — package excel yang dipakai cuma
  // baca/tulis format .xlsx (OOXML), bukan .xls biner lama.

  static const _pdfExts = {'pdf'};
  static const _spreadsheetExts = {'xlsx'};

  bool get isPdf => !isFolder && _pdfExts.contains(extension);
  bool get isSpreadsheet => !isFolder && _spreadsheetExts.contains(extension);
}
