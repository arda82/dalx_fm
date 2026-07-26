// features/task_queue/task_queue_screen.dart
//
// Layar Task Queue sesuai mockup yang disetujui: daftar task dengan
// progress bar, tombol pause/resume, cancel, dan "Hapus selesai".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_strings.dart';
import 'task.dart';
import 'task_queue.dart';

const _dalxAccent = Color(0xFF0A84FF);

class TaskQueueScreen extends ConsumerWidget {
  const TaskQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final tasks = ref.watch(taskQueueProvider);
    final notifier = ref.read(taskQueueProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.taskQueueTitle),
        actions: [
          TextButton(
            onPressed: tasks.any((t) => t.isDone) ? notifier.clearCompleted : null,
            child: Text(strings.clearCompleted),
          ),
        ],
      ),
      body: tasks.isEmpty
          ? Center(child: Text(strings.noRunningTasks))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                return _TaskCard(task: tasks[index], notifier: notifier);
              },
            ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DalXTask task;
  final TaskQueue notifier;

  const _TaskCard({required this.task, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isDone = task.status == TaskStatus.completed;
    final isPaused = task.status == TaskStatus.paused;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isDone ? _dalxAccent.withOpacity(0.15) : Colors.grey.shade200,
                  child: Icon(
                    isDone ? Icons.check : _iconForType(task.type),
                    size: 18,
                    color: isDone ? _dalxAccent : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _taskTitle(strings, task),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
                      ),
                      Text(
                        '${_operationLabel(strings, task.type)}${task.errorMessage != null ? " · ${task.errorMessage}" : ""}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (!isDone) ...[
                  IconButton(
                    icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, size: 20),
                    onPressed: () => isPaused ? notifier.resume(task.id) : notifier.pause(task.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.red),
                    onPressed: () => notifier.cancel(task.id),
                  ),
                ],
              ],
            ),
            if (!isDone) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 5,
                  backgroundColor: Colors.grey.shade200,
                  color: isPaused ? Colors.grey : _dalxAccent,
                ),
              ),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  isPaused ? strings.taskPaused : '${(task.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _taskTitle(AppStrings strings, DalXTask task) {
    final firstName = task.sourcePaths.first.split('/').last;
    if (task.sourcePaths.length == 1) return firstName;
    return '$firstName ${strings.andMore(task.sourcePaths.length - 1)}';
  }

  // Label dilokalisasi di sini (bukan task.operationLabel di
  // task.dart) karena DalXTask model murni, tidak punya akses
  // BuildContext buat AppStrings.of(context).
  String _operationLabel(AppStrings strings, TaskType type) {
    switch (type) {
      case TaskType.copy:
        return strings.taskCopy;
      case TaskType.move:
        return strings.taskMove;
      case TaskType.delete:
        return strings.taskDelete;
      case TaskType.compress:
        return strings.taskCompress;
      case TaskType.extract:
        return strings.taskExtract;
    }
  }

  IconData _iconForType(TaskType type) {
    switch (type) {
      case TaskType.copy:
        return Icons.copy;
      case TaskType.move:
        return Icons.content_cut;
      case TaskType.delete:
        return Icons.delete_outline;
      case TaskType.compress:
        return Icons.folder_zip_outlined;
      case TaskType.extract:
        return Icons.unarchive_outlined;
    }
  }
}
