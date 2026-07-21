// features/favorites/favorites_screen.dart
//
// Layar Favorites. Tap folder favorit → pindah ke ExplorerScreen di
// path itu. Tap file favorit → snackbar info (viewer menyusul Fase 3/6).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../explorer_ui/explorer_screen.dart';
import 'favorites_service.dart';

const _dalxAccent = Color(0xFF0A84FF);

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).toList()..sort();
    final notifier = ref.read(favoritesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: favorites.isEmpty
          ? const Center(child: Text('Belum ada item favorit'))
          : ListView.builder(
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final path = favorites[index];
                final name = path.split('/').last;
                final isFolder = FileSystemEntity.isDirectorySync(path);

                return ListTile(
                  leading: Icon(
                    isFolder ? Icons.folder : Icons.insert_drive_file_outlined,
                    color: isFolder ? _dalxAccent : Colors.grey,
                  ),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(path,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.star, color: _dalxAccent),
                    onPressed: () => notifier.remove(path),
                  ),
                  onTap: () {
                    if (isFolder) {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => ExplorerScreen(rootPath: path)));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Viewer file belum tersedia (menyusul Fase 3/6)')),
                      );
                    }
                  },
                );
              },
            ),
    );
  }
}