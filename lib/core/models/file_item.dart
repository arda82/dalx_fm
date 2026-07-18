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
}
