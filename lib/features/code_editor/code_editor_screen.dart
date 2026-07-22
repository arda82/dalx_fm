// features/code_editor/code_editor_screen.dart
//
// Fase 4 — Code Editor. Pakai re_editor (bukan TextField biasa)
// karena dioptimalkan buat file teks besar dan sudah punya logic
// find/replace bawaan (lihat CodeFindController) — cuma UI panelnya
// yang wajib dibuat sendiri, itu yang ada di _FindReplacePanel di
// bawah.
//
// Selection Toolbar (Copy/Cut/Paste/Select All) muncul otomatis
// pas long-press teks yang disorot — logic-nya juga sudah ada di
// re_editor lewat MobileSelectionToolbarController, kita cuma
// suplai builder isi popup-nya (_buildSelectionToolbar). Select
// manual (drag) dan replace/delete teks yang disorot (ketik di
// atasnya / backspace) sudah otomatis dari re_editor, tidak perlu
// kode tambahan.
//
// Save ke file lewat dart:io langsung (operasi ringan seperti
// Rename di file_engine, BUKAN lewat TaskQueue — sesuai pembagian
// yang sudah ada: TaskQueue untuk operasi berat Copy/Move/Delete).
//
// File berukuran > 3 MB dibuka read-only (bukan diblokir total) —
// TextField-based editor bisa lag di teks sangat panjang; ambang
// batas ini konservatif dan bisa dinaikkan kalau di device asli
// ternyata masih lancar di ukuran lebih besar.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'language_detector.dart';

const _dalxAccent = Color(0xFF0A84FF);
const _editorBackground = Color(0xFF1E1E1E);
const _maxEditableSizeBytes = 3 * 1024 * 1024; // 3 MB

class CodeEditorScreen extends StatefulWidget {
  final String path;

  const CodeEditorScreen({super.key, required this.path});

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late final CodeLineEditingController _controller;
  late final CodeFindController _findController;
  late final MobileSelectionToolbarController _toolbarController;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  bool _readOnlyTooLarge = false;
  String? _errorMessage;
  String _originalText = '';

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText('');
    _findController = CodeFindController(_controller);
    _toolbarController = MobileSelectionToolbarController(
      builder: _buildSelectionToolbar,
    );
    _loadFile();
  }

  @override
  void dispose() {
    _findController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final file = File(widget.path);
      final size = await file.length();
      final tooLarge = size > _maxEditableSizeBytes;
      final content = await file.readAsString();
      if (!mounted) return;

      _originalText = content;
      _controller.text = content;
      _controller.addListener(_onTextChanged);

      setState(() {
        _isLoading = false;
        _readOnlyTooLarge = tooLarge;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _onTextChanged() {
    final changed = _controller.text != _originalText;
    if (changed != _hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = changed);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await File(widget.path).writeAsString(_controller.text);
      _originalText = _controller.text;
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _hasUnsavedChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tersimpan')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $e')),
      );
    }
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Perubahan belum disimpan'),
        content: const Text('Keluar tanpa menyimpan perubahan?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _extensionOf(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return '';
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  // ---------------- Selection Toolbar (Copy/Cut/Paste/Select All) ----------------
  //
  // Dipanggil re_editor sendiri lewat MobileSelectionToolbarController
  // begitu user long-press teks (baik ada seleksi maupun cuma taruh
  // kursor). Kita cuma nentuin tombol apa saja yang relevan buat
  // kondisi saat itu — semua aksinya (copy/cut/paste/selectAll) sudah
  // ada di CodeLineEditingController, tidak perlu implementasi manual.
  Widget _buildSelectionToolbar({
    required TextSelectionToolbarAnchors anchors,
    required BuildContext context,
    required CodeLineEditingController controller,
    required VoidCallback onDismiss,
    required VoidCallback onRefresh,
  }) {
    final hasSelection = !controller.selection.isCollapsed;
    final canEdit = !_readOnlyTooLarge;

    final labels = <String>[];
    final actions = <VoidCallback>[];

    if (hasSelection) {
      labels.add('Copy');
      actions.add(() {
        controller.copy();
        onDismiss();
      });
      if (canEdit) {
        labels.add('Cut');
        actions.add(() {
          controller.cut();
          onDismiss();
        });
      }
    }
    if (canEdit) {
      labels.add('Paste');
      actions.add(() {
        controller.paste();
        onDismiss();
      });
    }
    if (!controller.isAllSelected) {
      labels.add('Select All');
      actions.add(() {
        controller.selectAll();
        onRefresh();
      });
    }

    if (labels.isEmpty) return const SizedBox.shrink();

    return TextSelectionToolbar(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      children: List.generate(labels.length, (i) {
        return TextSelectionToolbarTextButton(
          padding: TextSelectionToolbarTextButton.getPadding(i, labels.length),
          onPressed: actions[i],
          child: Text(labels[i]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.path.split('/').last;
    final language = languageForExtension(_extensionOf(fileName));

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirmed = await _confirmDiscardIfNeeded();
        if (confirmed && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: _editorBackground,
        appBar: AppBar(
          backgroundColor: _editorBackground,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_hasUnsavedChanges)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.circle, size: 8, color: _dalxAccent),
                ),
            ],
          ),
          actions: _isLoading || _errorMessage != null
              ? null
              : [
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Find & Replace',
                    onPressed: () => _findController.findMode(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: 'Undo',
                    onPressed: _readOnlyTooLarge
                        ? null
                        : () {
                            if (_controller.canUndo) _controller.undo();
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo),
                    tooltip: 'Redo',
                    onPressed: _readOnlyTooLarge
                        ? null
                        : () {
                            if (_controller.canRedo) _controller.redo();
                          },
                  ),
                  IconButton(
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _dalxAccent),
                          )
                        : const Icon(Icons.save_outlined),
                    tooltip: 'Save',
                    onPressed: (_readOnlyTooLarge || _isSaving) ? null : _save,
                  ),
                ],
        ),
        body: _buildBody(language),
      ),
    );
  }

  Widget _buildBody(CodeLanguage? language) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _dalxAccent));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Gagal membuka file: $_errorMessage',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_readOnlyTooLarge)
          Container(
            width: double.infinity,
            color: Colors.orange.withOpacity(0.15),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Text(
              'File berukuran besar (>3 MB) — dibuka sebagai read-only.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ),
        Expanded(
          child: CodeEditor(
            controller: _controller,
            findController: _findController,
            toolbarController: _toolbarController,
            readOnly: _readOnlyTooLarge,
            wordWrap: false,
            style: CodeEditorStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              backgroundColor: _editorBackground,
              textColor: Colors.white,
              cursorColor: _dalxAccent,
              selectionColor: _dalxAccent.withOpacity(0.35),
              highlightColor: _dalxAccent.withOpacity(0.25),
              codeTheme: language == null
                  ? null
                  : CodeHighlightTheme(
                      languages: {
                        language.id: CodeHighlightThemeMode(mode: language.mode),
                      },
                      theme: atomOneDarkTheme,
                    ),
            ),
            indicatorBuilder: (context, editingController, chunkController, notifier) {
              return Row(
                children: [
                  DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                  ),
                  DefaultCodeChunkIndicator(
                    width: 20,
                    controller: chunkController,
                    notifier: notifier,
                  ),
                ],
              );
            },
            findBuilder: (context, controller, readOnly) => _FindReplacePanel(
              controller: controller,
              readOnly: readOnly,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------- Find & Replace Panel (UI custom, Fase 4) ----------------
//
// re_editor menyediakan LOGIC find/replace lewat CodeFindController
// (pattern matching, next/previous match, replace, replace all,
// toggle case-sensitive/regex) tapi TIDAK menyediakan UI panel bawaan
// — itu memang harus dibuat sendiri oleh yang pakai package-nya. Ini
// versi minimal DalX: satu baris input pencarian + counter match +
// next/previous + toggle case/regex, dan kalau bukan read-only ada
// baris kedua untuk input pengganti + Replace/Replace All.

class _FindReplacePanel extends StatefulWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  const _FindReplacePanel({required this.controller, required this.readOnly});

  @override
  Size get preferredSize => Size.fromHeight(readOnly ? 44 : 88);

  @override
  State<_FindReplacePanel> createState() => _FindReplacePanelState();
}

class _FindReplacePanelState extends State<_FindReplacePanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onValueChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onValueChanged);
    super.dispose();
  }

  void _onValueChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final option = value?.option;
    final result = value?.result;
    final matchCount = result?.matches.length ?? 0;
    final currentIndex = (result != null && matchCount > 0) ? result.index + 1 : 0;

    return Material(
      color: const Color(0xFF2A2A2A),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller.findInputController,
                    focusNode: widget.controller.findInputFocusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Cari...',
                      hintStyle: TextStyle(color: Colors.white38),
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Text(
                  matchCount == 0 ? '0/0' : '$currentIndex/$matchCount',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 20),
                  onPressed: matchCount == 0 ? null : widget.controller.previousMatch,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 20),
                  onPressed: matchCount == 0 ? null : widget.controller.nextMatch,
                ),
                IconButton(
                  icon: Icon(
                    Icons.text_fields,
                    size: 18,
                    color: (option?.caseSensitive ?? false) ? _dalxAccent : Colors.white38,
                  ),
                  tooltip: 'Case sensitive',
                  onPressed: widget.controller.toggleCaseSensitive,
                ),
                IconButton(
                  icon: Icon(
                    Icons.code,
                    size: 18,
                    color: (option?.regex ?? false) ? _dalxAccent : Colors.white38,
                  ),
                  tooltip: 'Regex',
                  onPressed: widget.controller.toggleRegex,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: widget.controller.close,
                ),
              ],
            ),
            if (!widget.readOnly)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.controller.replaceInputController,
                      focusNode: widget.controller.replaceInputFocusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Ganti dengan...',
                        hintStyle: TextStyle(color: Colors.white38),
                        isDense: true,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: matchCount == 0 ? null : widget.controller.replaceMatch,
                    child: const Text('Replace', style: TextStyle(color: _dalxAccent, fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: matchCount == 0 ? null : widget.controller.replaceAllMatches,
                    child: const Text('Replace All', style: TextStyle(color: _dalxAccent, fontSize: 12)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
