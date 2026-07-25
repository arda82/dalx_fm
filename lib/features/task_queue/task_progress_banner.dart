// features/task_queue/task_progress_banner.dart
//
// Banner mengambang yang muncul di layar MANA PUN selagi ada task
// aktif di Task Queue (Copy/Move/Delete/Compress/Extract) — dipasang
// di level app shell (lihat main.dart, MaterialApp.builder), BUKAN
// per-screen, supaya persist walau user pindah-pindah layar.
//
// SIFATNYA NON-BLOCKING — user tetap bisa browsing folder lain selagi
// proses jalan, konsisten sama filosofi Task Queue dari awal ("UI
// tidak nge-block", lihat header task_queue.dart).
//
// PENTING soal tombol aksi: operasi native (compress 7z, extract
// 7z/RAR — Fase 8 Pilar #2) TIDAK BISA di-cancel di tengah jalan
// (loop-nya di Kotlin, bukan Dart, lihat catatan _runNativeArchiveOp
// di task_queue.dart). Buat task jenis ini, tombolnya "Sembunyikan"
// (banner hilang dari layar, proses TETAP lanjut di background) —
// BUKAN "Batalkan", supaya tidak menyesatkan user mengira prosesnya
// beneran berhenti.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'task.dart';
import 'task_queue.dart';
import 'task_queue_screen.dart';

const _dalxAccent = Color(0xFF0A84FF);

class TaskProgressBanner extends ConsumerStatefulWidget {
  const TaskProgressBanner({super.key});

  @override
  ConsumerState<TaskProgressBanner> createState() => _TaskProgressBannerState();
}

class _TaskProgressBannerState extends ConsumerState<TaskProgressBanner> {
  // Task yang di-"Sembunyikan" user — banner-nya nggak muncul lagi
  // buat task ID ini walau masih isActive, TAPI proses aslinya tetap
  // lanjut di TaskQueue seperti biasa (state ini cuma soal tampilan).
  final Set<String> _dismissedTaskIds = {};

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(taskQueueProvider);
    final activeTask = tasks.where((t) => t.isActive && !_dismissedTaskIds.contains(t.id)).firstOrNull;

    // Task baru yang belum pernah di-dismiss otomatis "lupa" status
    // dismiss task LAMA yang sudah selesai — bersihin set biar nggak
    // numpuk terus selama app hidup (memory kecil, tapi tetap rapi).
    _dismissedTaskIds.removeWhere((id) => !tasks.any((t) => t.id == id && t.isActive));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
        child: child,
      ),
      child: activeTask == null
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : _BannerCard(key: ValueKey(activeTask.id), task: activeTask, onDismiss: () {
              setState(() => _dismissedTaskIds.add(activeTask.id));
            }),
    );
  }
}

class _BannerCard extends ConsumerWidget {
  final DalXTask task;
  final VoidCallback onDismiss;

  const _BannerCard({super.key, required this.task, required this.onDismiss});

  /// Operasi native (compress 7z, extract 7z/RAR) TIDAK bisa
  /// di-cancel — lihat catatan header file ini & task_queue.dart.
  /// Dideteksi dari EKSTENSI (bukan field terpisah di DalXTask),
  /// konsisten sama cara task_queue.dart sendiri nentuin routing
  /// native/Dart (lihat TaskQueue.extract/compress).
  bool get _isCancelable {
    if (task.type == TaskType.rotatePdf) return false;
    if (task.type == TaskType.compress) {
      final path = (task.destinationPath ?? '').toLowerCase();
      return !path.endsWith('.7z');
    }
    if (task.type == TaskType.extract) {
      final path = task.sourcePaths.isNotEmpty ? task.sourcePaths.first.toLowerCase() : '';
      return !(path.endsWith('.7z') || path.endsWith('.rar'));
    }
    return true; // copy/move/delete selalu bisa di-cancel
  }

  IconData get _icon {
    switch (task.type) {
      case TaskType.copy:
        return Icons.copy;
      case TaskType.move:
        return Icons.drive_file_move;
      case TaskType.delete:
        return Icons.delete;
      case TaskType.compress:
        return Icons.folder_zip;
      case TaskType.extract:
        return Icons.unarchive;
      case TaskType.rotatePdf:
        return Icons.rotate_right;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = (task.progress * 100).round();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Material(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          elevation: 6,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const TaskQueueScreen()),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(_icon, color: _dalxAccent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${task.operationLabel} — $percent%',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: task.progress,
                            minHeight: 4,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(_dalxAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isCancelable)
                    TextButton(
                      onPressed: () => ref.read(taskQueueProvider.notifier).cancel(task.id),
                      child: const Text('Batalkan', style: TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                    )
                  else
                    TextButton(
                      onPressed: onDismiss,
                      child: const Text('Sembunyikan', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
