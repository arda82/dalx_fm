// features/code_editor/code_editor_screen.dart
//
// Fase 4 — Code Editor. Pakai re_editor (bukan TextField biasa)
// karena dioptimalkan buat file teks besar dan sudah punya logic
// find/replace bawaan (lihat CodeFindController) — cuma UI panelnya
// yang wajib dibuat sendiri, itu yang ada di _FindReplacePanel di
// bawah.
//
// --- AppBar minimal ---
// Toolbar atas cuma nampilin nama file + path (di bawahnya) + titik
// biru kalau ada perubahan belum disimpan. SEMUA aksi (Cari & Ganti,
// Select All, Indent, Outdent, Word Wrap, Undo, Redo, Save) ada di
// menu titik-tiga (More) di kanan.
//
// --- Find & Replace Panel ---
// PENTING: CodeFindController.value bertipe CodeFindValue? (nullable).
// value == null berarti mode Cari belum aktif (findMode() belum
// dipanggil, atau sudah di-close()) — di kondisi itu panel WAJIB
// render kosong (SizedBox.shrink, preferredSize nol), supaya panel
// beneran hilang total sampai user tap "Cari & Ganti" dari menu More.
// Kalau ini tidak dicek, findBuilder tetap dipanggil terus oleh
// CodeEditor dan panel akan selalu tampil sejak file dibuka.
//
// --- Selection Toolbar (Copy/Cut/Paste/Select All) ---
// Muncul otomatis pas long-press teks yang disorot lewat
// MobileSelectionToolbarController, dibungkus Theme gelap biar nggak
// putih-menyala di atas editor gelap.
//
// Save ke file lewat dart:io langsung (operasi ringan seperti
// Rename di file_engine, BUKAN lewat TaskQueue).
//
// File berukuran > 3 MB dibuka read-only — TextField-based editor
// bisa lag di teks sangat panjang.
//
// --- Preview HTML/CSS/JS ---
// Cuma muncul kalau isHtmlExtension() true. In-place (bukan push
// screen baru) lewat IndexedStack, sama pola dengan
// xlsx_editor_screen.dart pindah sheet — supaya kode editor dan
// WebView tetap hidup di memori pas gonta-ganti mode, dan tombol
// Refresh bisa baca _controller.text langsung dari sumber yang sama
// (bukan snapshot beku yang dikirim lewat constructor).
//
// Refresh SENGAJA manual (tombol di preview toolbar), bukan auto tiap
// ketik — auto-reload WebView tiap keystroke berat dan bikin preview
// nge-lag pas user masih ngetik.
//
// Back fisik/gesture pas mode Preview: 1x back HARUS balik ke mode
// Kode dulu, BUKAN langsung keluar screen. Makanya canPop di PopScope
// harus false selama _mode == EditorMode.preview, terlepas dari
// _hasUnsavedChanges.
//
// CATATAN BELUM TERVERIFIKASI DI DEVICE: baseUrl file:// dipakai biar
// <link href="style.css"> dan <script src="script.js"> di HTML bisa
// resolve file tetangganya di folder yang sama. Android WebView versi
// baru kadang membatasi akses file:// lintas origin. Kalau CSS/JS
// eksternal gak muncul pas dites di device, fallback-nya: baca isi
// file .css/.js terkait manual lalu inject inline ke <style>/<script>
// sebelum loadHtmlString — jangan andalkan baseUrl doang.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/monokai.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'language_detector.dart';

/// Mode tampilan code_editor_screen — Kode (default) atau Preview
/// (WebView render HTML, cuma tersedia untuk file HTML).
enum EditorMode { code, preview }

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

  EditorMode _mode = EditorMode.code;
  WebViewController? _webViewController;

  bool get _isHtml => isHtmlExtension(_extensionOf(widget.path.split('/').last));

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

  // ---------------- Mode Kode <-> Preview ----------------

  bool _previewLoading = false;

  void _setMode(EditorMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    if (mode == EditorMode.preview) {
      _webViewController ??= WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white);
      _refreshPreview();
    }
  }

  // Baca ulang _controller.text (bukan _originalText) — sengaja gak
  // butuh file tersimpan dulu, biar user bisa preview draft yang
  // belum di-save.
  //
  // CSS/JS lokal (href/src relatif, bukan http(s)://) di-inline
  // manual ke <style>/<script> sebelum dirender — baseUrl file://
  // TERBUKTI gak reliable resolve resource eksternal di Android
  // WebView versi baru (dicoba, gak jalan). Jangan balik ke pendekatan
  // baseUrl lagi tanpa alasan kuat.
  Future<void> _refreshPreview() async {
    final controller = _webViewController;
    if (controller == null) return;
    setState(() => _previewLoading = true);
    final inlined = await _inlineLocalAssets(_controller.text);
    if (!mounted) return;
    setState(() => _previewLoading = false);
    await controller.loadHtmlString(inlined, baseUrl: 'file://$_parentPath/');
  }

  // ---------------- Inline CSS/JS lokal ke dalam HTML ----------------
  //
  // Pakai package:html (DOM parser beneran, bukan regex) — resmi dari
  // tim Dart, pure Dart (gak nambah beban native/Gradle). Nangkep
  // kasus yang regex gak bisa: atribut multi-baris, urutan atribut
  // acak, tag self-closing tanpa "/>", dll.
  //
  // CATATAN: document.outerHtml di bawah adalah hasil serialisasi
  // ULANG dari DOM tree, bukan salinan teks asli 1:1 (spasi/quote
  // style bisa sedikit berbeda). Ini AMAN untuk preview karena cuma
  // dikirim ke WebView buat dirender, TIDAK PERNAH ditulis balik ke
  // file — jalur Save tetap pakai _controller.text apa adanya, gak
  // lewat fungsi ini sama sekali.

  bool _isRemoteUrl(String path) {
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('//');
  }

  Future<String?> _readSiblingFile(String relativePath) async {
    try {
      final file = File('$_parentPath/$relativePath');
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<String> _inlineLocalAssets(String rawHtml) async {
    final document = html_parser.parse(rawHtml);

    for (final link in document.querySelectorAll('link[rel="stylesheet"]')) {
      final href = link.attributes['href'];
      if (href == null || href.isEmpty || _isRemoteUrl(href)) continue;
      final content = await _readSiblingFile(href);
      if (content == null) continue; // file gak ketemu -> biarin tag link asli
      final styleTag = dom.Element.tag('style')..text = content;
      link.replaceWith(styleTag);
    }

    for (final script in document.querySelectorAll('script[src]')) {
      final src = script.attributes['src'];
      if (src == null || src.isEmpty || _isRemoteUrl(src)) continue;
      final content = await _readSiblingFile(src);
      if (content == null) continue;
      final inlineScript = dom.Element.tag('script')..text = content;
      script.replaceWith(inlineScript);
    }

    return document.outerHtml;
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

  // ---------------- Run di Termux ----------------
  //
  // Channel berdiri sendiri (bukan numpang ke NativeBridge yang
  // sudah ada) — sengaja, karena file MainActivity.kt/NativeBridge.kt
  // saat ini belum di-upload ke sesi ini buat di-diff. Kalau nanti
  // mau dikonsolidasi ke channel utama, aman dipindah belakangan,
  // logic Dart-nya gak berubah, cuma nama channel-nya.
  static const MethodChannel _termuxChannel = MethodChannel('com.dalx.app/termux');

  // Internal Storage di Android SELALU di "/storage/emulated/0" —
  // path ini fixed, gak tergantung device. SD Card/USB OTG mount di
  // path lain (mis. "/storage/1234-5678"), jadi cukup dicek prefix
  // ini doang, gak perlu tau storageAccessProvider detail.
  bool get _isOnInternalStorage => widget.path.startsWith('/storage/emulated/0/');

  Future<void> _runInTermux() async {
    if (!_isOnInternalStorage) {
      _showSnack(
        'File ini ada di SD Card/USB OTG — Termux gak bisa akses langsung. '
        'Pindahin dulu ke Internal Storage, baru coba Run di Termux lagi.',
      );
      return;
    }

    final interpreter = interpreterCommandFor(_extensionOf(widget.path.split('/').last));
    if (interpreter == null) return; // safety net, seharusnya menu udah gak muncul

    // Sengaja BUKAN jalanin interpreter langsung sebagai
    // RUN_COMMAND_PATH — begitu proses itu selesai (apalagi script
    // pendek), Termux otomatis nutup sesi & activity-nya (behavior
    // default terminal, bukan sesuatu yang DalX minta). Dibungkus
    // lewat bash -c yang di ujungnya nunggu Enter, biar user sempet
    // baca output sebelum Termux ketutup.
    final workdirQ = _shellQuote(_parentPath);
    final fileQ = _shellQuote(widget.path.split('/').last);
    final shellCommand = "cd $workdirQ && $interpreter $fileQ; "
        "status=\$?; echo; echo \"--- Selesai (exit code: \$status) ---\"; "
        "read -p 'Tekan Enter untuk menutup...' _";

    try {
      await _termuxChannel.invokeMethod('runCommand', {
        'workdir': _parentPath,
        'shellCommand': shellCommand,
      });
    } on PlatformException catch (e) {
      String message;
      switch (e.code) {
        case 'TERMUX_NOT_FOUND':
          message = 'Termux belum terinstall. Install dulu dari F-Droid/Play Store.';
          break;
        case 'TERMUX_PERMISSION_DENIED':
          message = 'DalX belum diizinkan kirim command ke Termux. '
              'Cek izin RUN_COMMAND di Settings > Apps > DalX.';
          break;
        default:
          message = 'Gagal membuka Termux: ${e.message ?? 'unknown error'}';
      }
      _showSnack(message);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Bungkus value jadi single-quoted string buat bash — aman walau
  // ada spasi/tanda kutip di nama folder atau file.
  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
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
      case 'preview':
        _setMode(EditorMode.preview);
        break;
      case 'run_termux':
        _runInTermux();
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
      if (_isHtml) ...[
        const PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: 'preview',
          child: _MenuRow(icon: Icons.visibility_outlined, label: 'Preview', active: _mode == EditorMode.preview),
        ),
      ],
      if (interpreterCommandFor(_extensionOf(widget.path.split('/').last)) != null) ...[
        const PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: 'run_termux',
          child: _MenuRow(icon: Icons.terminal, label: 'Run di Termux'),
        ),
      ],
    ];
  }

  // ---------------- Selection Toolbar (Copy/Cut/Paste/Select All) ----------------
  //
  // Dipanggil re_editor sendiri lewat MobileSelectionToolbarController
  // begitu user long-press teks. Dibungkus Theme gelap supaya warna
  // popup-nya konsisten sama tema gelap editor.
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
      // Mode preview: canPop selalu false, terlepas dari
      // _hasUnsavedChanges — back pertama WAJIB balik ke mode Kode
      // dulu, baru back kedua (dari mode Kode) ikut aturan unsaved
      // changes yang sudah ada.
      canPop: _mode == EditorMode.code && !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_mode == EditorMode.preview) {
          _setMode(EditorMode.code);
          return;
        }
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
          toolbarHeight: 62,
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
              const SizedBox(height: 3),
              Text(
                _parentPath,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
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
        body: _isHtml
            ? IndexedStack(
                index: _mode == EditorMode.code ? 0 : 1,
                children: [
                  _buildBody(language),
                  _buildPreviewBody(),
                ],
              )
            : _buildBody(language),
        floatingActionButton: (_isHtml && !_isLoading && _errorMessage == null)
            ? _buildPreviewToggle()
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  // ---------------- Body Preview (WebView) ----------------

  Widget _buildPreviewBody() {
    final controller = _webViewController;
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: _panelBackground,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Preview • ${widget.path.split('/').last}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: _previewLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _dalxAccent),
                      )
                    : const Icon(Icons.refresh, color: Colors.white70, size: 20),
                tooltip: 'Refresh preview',
                onPressed: _previewLoading ? null : _refreshPreview,
              ),
            ],
          ),
        ),
        Expanded(
          child: controller == null
              ? const SizedBox.shrink()
              : WebViewWidget(controller: controller),
        ),
      ],
    );
  }

  // ---------------- Floating pill toggle Kode <-> Preview ----------------

  Widget _buildPreviewToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _panelBackground,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(label: 'Kode', mode: EditorMode.code, icon: Icons.code),
          _buildToggleButton(label: 'Preview', mode: EditorMode.preview, icon: Icons.visibility_outlined),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required EditorMode mode,
    required IconData icon,
  }) {
    final active = _mode == mode;
    return GestureDetector(
      onTap: () => _setMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? _dalxAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? Colors.white : Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
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
                      theme: monokai,
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
// PENTING: controller.value bertipe CodeFindValue? — null berarti
// mode Cari belum aktif / sudah ditutup. Kondisi ini WAJIB dicek di
// preferredSize DAN build(), supaya panel benar-benar hilang total
// (bukan cuma kosong "0/0") sampai user membuka mode Cari lagi lewat
// menu More.

class _FindReplacePanel extends StatefulWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  const _FindReplacePanel({required this.controller, required this.readOnly});

  @override
  Size get preferredSize {
    if (controller.value == null) return Size.zero;
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

    // value == null -> mode Cari belum aktif / sudah ditutup. Panel
    // wajib kosong total, bukan cuma nampilin "0/0".
    if (value == null) return const SizedBox.shrink();

    final option = value.option;
    final result = value.result;
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
                    color: option.caseSensitive ? _dalxAccent : Colors.white54,
                  ),
                  tooltip: 'Case sensitive',
                  onPressed: widget.controller.toggleCaseSensitive,
                ),
                IconButton(
                  icon: Icon(
                    Icons.code,
                    size: 18,
                    color: option.regex ? _dalxAccent : Colors.white54,
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
