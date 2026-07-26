// features/task_queue/task.dart
//
// Model satu item pekerjaan di Task Queue — Copy/Move/Delete, dll.
// Semua operasi yang MENGUBAH filesystem wajib lewat sini (lihat
// ARCHITECTURE.md bagian 7), supaya UI tidak nge-block dan user bisa
// pause/resume/cancel.

enum TaskType { copy, move, delete, compress, extract }

enum TaskStatus { queued, running, paused, completed, failed, cancelled }

/// Strategi resolusi konflik saat Paste menemukan nama yang sudah ada
/// di folder tujuan. Dipilih user lewat dialog di explorer_screen
/// SEBELUM task dikirim ke TaskQueue — satu strategi berlaku untuk
/// semua item yang konflik dalam satu batch paste itu.
enum ConflictStrategy {
  /// Item yang namanya bentrok tidak disalin/dipindah sama sekali.
  skip,

  /// Item tujuan yang sudah ada ditimpa. Untuk file ini perilaku
  /// default dart:io (File.copy menimpa otomatis); untuk folder,
  /// isinya digabung (merge) dan file yang bentrok ikut ditimpa.
  overwrite,

  /// Item disalin/dipindah dengan nama baru "nama (1)", "nama (2)",
  /// dst — angka pertama yang belum dipakai di folder tujuan.
  renameAuto,
}

class DalXTask {
  final String id;
  final TaskType type;
  final List<String> sourcePaths;
  final String? destinationPath; // null untuk delete
  final TaskStatus status;
  final double progress; // 0.0 - 1.0
  final String? errorMessage;

  const DalXTask({
    required this.id,
    required this.type,
    required this.sourcePaths,
    this.destinationPath,
    this.status = TaskStatus.queued,
    this.progress = 0.0,
    this.errorMessage,
  });

  DalXTask copyWith({
    TaskStatus? status,
    double? progress,
    String? errorMessage,
  }) {
    return DalXTask(
      id: id,
      type: type,
      sourcePaths: sourcePaths,
      destinationPath: destinationPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// Label ringkas untuk tampil di UI Task Queue, mis. "Menyalin".
  String get operationLabel {
    switch (type) {
      case TaskType.copy:
        return 'Menyalin';
      case TaskType.move:
        return 'Memindahkan';
      case TaskType.delete:
        return 'Menghapus';
      case TaskType.compress:
        return 'Mengompres';
      case TaskType.extract:
        return 'Mengekstrak';
    }
  }

  bool get isActive => status == TaskStatus.running || status == TaskStatus.paused;
  bool get isDone => status == TaskStatus.completed || status == TaskStatus.failed || status == TaskStatus.cancelled;
}
