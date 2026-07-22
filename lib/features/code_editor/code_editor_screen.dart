// features/code_editor/code_editor_screen.dart
//
// Fase 4 — Code Editor. Pakai re_editor (bukan TextField biasa)
// karena dioptimalkan buat file teks besar dan sudah punya logic
// find/replace bawaan (lihat CodeFindController) — cuma UI panelnya
// yang wajib dibuat sendiri, itu yang ada di _FindReplacePanel di
// bawah.
//
// --- AppBar minimal ---
// Toolbar atas SENGAJA cuma nampilin nama file + path (di bawahnya,
// kecil) + titik biru kalau ada perubahan belum disimpan. SEMUA aksi
// (Cari & Ganti, Select All, Indent, Outdent, Word Wrap, Undo, Redo,
// Save) dipindah ke menu titik-tiga (More) di kanan — supaya toolbar
// atas tetap ringkas dan nggak menutupi baris pertama kode.
//
// --- Selection Toolbar (Copy/Cut/Paste/Select All) ---
// Muncul otomatis pas long-press teks yang disorot — logic-nya sudah
// ada di re_editor lewat MobileSelectionToolbarController, kita cuma
// suplai builder isi popup-nya (_buildSelectionToolbar), dibungkus
// Theme gelap biar nggak putih-menyala di atas editor gelap. Select
// manual (drag) dan replace/delete teks yang disorot (ketik di
// atasnya / backspace) sudah otomatis dari re_editor.
//
// Save ke file lewat dart:io langsung (operasi ringan seperti
// Rename di file_engine, BUKAN lewat TaskQueue).
//
// File berukuran > 3 MB dibuka read-only — TextField-based editor
// bisa lag di teks sangat panjang.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'language_detector.dart';

const _dalxAccent = Color(0xFF0A84FF);
const _editorBackground = Color(0xFF1E1E1E);
const _panelBackground = Color(0xFF2A2A2A);
const _inputFillColor = Color(0xFF3A3A3A);
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
  bool _wordWrap = false;
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

  String get _parentPath {
    final idx = widget.path.lastIndexOf('/');
    return idx <= 0 ? '/' : widget.path.substring(0, idx);
  }

  // ---------------- Menu More (semua aksi toolbar) ----------------

  void _handleMenuAction(String value) {
    switch (value) {
      case 'find':
        _findController.findMode();
        break;
      case 'select_all':
        _controller.selectAll();
        break;
      case 'indent':
        _controller.applyIndent();
        break;
      case 'outdent':
        _controller.applyOutdent();
        break;
      case 'word_wrap':
        setState(() => _wordWrap = !_wordWrap);
        break;
      case 'undo':
        if (_controller.canUndo) _controller.undo();
        break;
      case 'redo':
        if (_controller.canRedo) _controller.redo();
        break;
      case 'save':
        _save();
        break;
    }
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    final canEdit = !_readOnlyTooLarge;
    return [
      const PopupMenuItem(value: 'find', child: _MenuRow(icon: Icons.search, label: 'Cari & Ganti')),
      const PopupMenuItem(value: 'select_all', child: _MenuRow(icon: Icons.select_all, label: 'Select All')),
      const PopupMenuDivider(height: 8),
      PopupMenuItem(
        value: 'indent',
        enabled: canEdit,
        child: _MenuRow(icon: Icons.format_indent_increase, label: 'Indent', dimmed: !canEdit),
      ),
      PopupMenuItem(
        value: 'outdent',
        enabled: canEdit,
        child: _MenuRow(icon: Icons.format_indent_decrease, label: 'Outdent', dimmed: !canEdit),
      ),
      PopupMenuItem(
        value: 'word_wrap',
        child: _MenuRow(icon: Icons.wrap_text, label: 'Word Wrap', active: _wordWrap),
      ),
      const PopupMenuDivider(height: 8),
      PopupMenuItem(
        value: 'undo',
        enabled: canEdit && _controller.canUndo,
        child: _MenuRow(icon: Icons.undo, label: 'Undo', dimmed: !(canEdit && _controller.canUndo)),
      ),
      PopupMenuItem(
        value: 'redo',
        enabled: canEdit && _controller.canRedo,
        child: _MenuRow(icon: Icons.redo, label: 'Redo', dimmed: !(canEdit && _controller.canRedo)),
      ),
      PopupMenuItem(
        value: 'save',
        enabled: canEdit && !_isSaving,
        child: _MenuRow(icon: Icons.save_outlined, label: 'Save', dimmed: !(canEdit && !_isSaving)),
      ),
    ];
  }

  // ---------------- Selection Toolbar (Copy/Cut/Paste/Select All) ----------------
  //
  // Dipanggil re_editor sendiri lewat MobileSelectionToolbarController
  // begitu user long-press teks. Dibungkus Theme gelap supaya warna
  // popup-nya (default Material bisa terang/putih) konsisten sama
  // tema gelap editor, bukan nyala mencolok.
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

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
              surface: _inputFillColor,
              onSurface: Colors.white,
            ),
      ),
      child: TextSelectionToolbar(
        anchorAbove: anchors.primaryAnchor,
        anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
        children: List.generate(labels.length, (i) {
          return TextSelectionToolbarTextButton(
            padding: TextSelectionToolbarTextButton.getPadding(i, labels.length),
            onPressed: actions[i],
            child: Text(
              labels[i],
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          );
        }),
      ),
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
          titleSpacing: 0,
          toolbarHeight: 60,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      fileName,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
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
              const SizedBox(height: 2),
              Text(
                _parentPath,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: _isLoading || _errorMessage != null
              ? null
              : [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    color: _panelBackground,
                    onSelected: _handleMenuAction,
                    itemBuilder: (context) => _buildMenuItems(),
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
            wordWrap: _wordWrap,
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

// ---------------- Baris menu (icon + label) buat PopupMenuItem ----------------

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool dimmed;

  const _MenuRow({
    required this.icon,
    required this.label,
    this.active = false,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = dimmed ? Colors.grey.shade600 : (active ? _dalxAccent : Colors.white);
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}

// ---------------- Find & Replace Panel (UI custom, Fase 4) ----------------
//
// re_editor menyediakan LOGIC find/replace lewat CodeFindController,
// UI panelnya dibuat sendiri di sini. Baris "Ganti dengan..." cuma
// muncul kalau kolom "Cari..." sudah diisi — biar panel nggak makan
// tempat pas baru dibuka (dan ikut mengecilkan risiko nutupin baris
// pertama kode). Input field dikasih kotak fill jelas (_inputFillColor)
// biar kontras sama panel, dan tombol Replace/Replace All dibikin
// lebih kalem (outlined/tonal, bukan teks biru terang polos).

class _FindReplacePanel extends StatefulWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  const _FindReplacePanel({required this.controller, required this.readOnly});

  @override
  Size get preferredSize {
    final hasQuery = controller.findInputController.text.isNotEmpty;
    final showReplaceRow = !readOnly && hasQuery;
    return Size.fromHeight(showReplaceRow ? 92 : 48);
  }

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

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),
      isDense: true,
      filled: true,
      fillColor: _inputFillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final option = value?.option;
    final result = value?.result;
    final matchCount = result?.matches.length ?? 0;
    final currentIndex = (result != null && matchCount > 0) ? result.index + 1 : 0;
    final showReplaceRow = !widget.readOnly && widget.controller.findInputController.text.isNotEmpty;

    return Material(
      color: _panelBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                    cursorColor: _dalxAccent,
                    decoration: _fieldDecoration('Cari...'),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  matchCount == 0 ? '0/0' : '$currentIndex/$matchCount',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
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
                    color: (option?.caseSensitive ?? false) ? _dalxAccent : Colors.white54,
                  ),
                  tooltip: 'Case sensitive',
                  onPressed: widget.controller.toggleCaseSensitive,
                ),
                IconButton(
                  icon: Icon(
                    Icons.code,
                    size: 18,
                    color: (option?.regex ?? false) ? _dalxAccent : Colors.white54,
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
            if (showReplaceRow) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.controller.replaceInputController,
                      focusNode: widget.controller.replaceInputFocusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      cursorColor: _dalxAccent,
                      decoration: _fieldDecoration('Ganti dengan...'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: matchCount == 0 ? null : widget.controller.replaceMatch,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: _dalxAccent.withOpacity(0.6)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Replace', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: matchCount == 0 ? null : widget.controller.replaceAllMatches,
                    style: FilledButton.styleFrom(
                      backgroundColor: _dalxAccent.withOpacity(0.85),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Replace All', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
