// features/explorer_ui/file_info_sheet.dart
//
// Bottom sheet File Info sesuai mockup yang disetujui: nama, lokasi,
// ukuran, tanggal dibuat/diubah, MIME type, izin dasar. Dibuka dari
// action mode toolbar (titik tiga > File Info) saat tepat 1 item
// terpilih.

import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/file_item.dart';

const _dalxAccent = Color(0xFF0A84FF);

Future<void> showFileInfoSheet(BuildContext context, FileItem item) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _FileInfoContent(item: item),
  );
}

class _FileInfoContent extends StatelessWidget {
  final FileItem item;

  const _FileInfoContent({required this.item});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ExtraInfo>(
      future: _loadExtraInfo(item),
      builder: (context, snapshot) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      item.isFolder ? Icons.folder : Icons.insert_drive_file_outlined,
                      color: item.isFolder ? _dalxAccent : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(
                          item.isFolder ? 'Folder' : (item.extension.isEmpty ? 'File' : item.extension.toUpperCase()),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(icon: Icons.folder_outlined, label: 'Lokasi', value: _parentPath(item.path)),
              if (!item.isFolder)
                _InfoRow(icon: Icons.data_usage_outlined, label: 'Ukuran', value: _formatSize(item.sizeBytes)),
              _InfoRow(icon: Icons.calendar_today_outlined, label: 'Diubah', value: _formatDate(item.modifiedAt)),
              if (!item.isFolder)
                _InfoRow(icon: Icons.info_outline, label: 'Tipe MIME', value: _mimeType(item.extension)),
              if (snapshot.hasData)
                _InfoRow(icon: Icons.shield_outlined, label: 'Izin', value: snapshot.data!.permissions),
            ],
          ),
        );
      },
    );
  }

  Future<_ExtraInfo> _loadExtraInfo(FileItem item) async {
    try {
      final stat = await FileStat.stat(item.path);
      // dart:io FileStat.modeString() memberi representasi rwx.
      return _ExtraInfo(permissions: stat.modeString());
    } catch (_) {
      return const _ExtraInfo(permissions: '-');
    }
  }

  String _parentPath(String path) {
    final idx = path.lastIndexOf('/');
    return idx <= 0 ? '/' : path.substring(0, idx);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year}, $hh:$mm';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _mimeType(String ext) {
    const map = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'pdf': 'application/pdf', 'zip': 'application/zip',
      'txt': 'text/plain', 'dart': 'text/x-dart', 'mp4': 'video/mp4',
    };
    return map[ext] ?? 'application/octet-stream';
  }
}

class _ExtraInfo {
  final String permissions;
  const _ExtraInfo({required this.permissions});
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }
}
