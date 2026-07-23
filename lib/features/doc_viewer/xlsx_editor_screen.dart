// features/doc_viewer/xlsx_editor_screen.dart
//
// Fase 6 — Doc Viewer bagian XLSX. Full cell-editing "kayak
// spreadsheet beneran" — pakai pluto_grid buat gridnya (udah ada
// cell editing, navigasi keyboard, tambah baris/kolom bawaan lewat
// PlutoGridStateManager) dan package excel (pure Dart) buat baca/
// tulis file .xlsx-nya.
//
// --- Model data ---
// Tiap cell disimpan sebagai String di PlutoCell (PlutoColumnType.text()
// di semua kolom, biar seragam & simpel) — konversi ke tipe asli
// Excel (Text/Int/Double/Bool) cuma dilakukan pas SAVE, lewat
// _parseCellValue. Ini trade-off sengaja: grid jadi jauh lebih
// sederhana (nggak perlu tipe kolom beda-beda per kolom kayak Excel
// asli), risikonya cuma pas nyimpen angka balik ke .xlsx, formatnya
// ditentukan ulang dari isi teksnya (bukan format asli cell itu).
//
// --- Formula & Date/Time cell ---
// Dibaca & ditampilkan apa adanya (formula ditampilkan "=SUM(...)",
// tanggal/waktu di-format seadanya), TAPI begitu user edit teks itu
// dan Save, cell itu ikut berubah jadi TextCellValue biasa (bukan
// FormulaCellValue/DateCellValue lagi). Ini batasan MVP — edit
// formula/tanggal "beneran" (tetap kalkulasi/tetap ke-format sebagai
// tanggal) di luar scope Fase 6.
//
// --- Multi-sheet ---
// Semua sheet dimuat sekaligus ke memori (IndexedStack, bukan lazy)
// supaya perubahan di sheet A nggak hilang pas pindah lihat sheet B.
// Tab sheet di bagian bawah layar, gaya mirip Excel/Google Sheets.
//
// --- AppBar ---
// Sama gaya kayak CodeEditorScreen: nama file + path + titik biru
// unsaved-indicator, semua aksi (Tambah Baris, Tambah Kolom, Save)
// di menu titik-tiga.

import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';

const _dalxAccent = Color(0xFF0A84FF);
const _editorBackground = Color(0xFF1E1E1E);
const _panelBackground = Color(0xFF2A2A2A);

class XlsxEditorScreen extends StatefulWidget {
  final String path;

  const XlsxEditorScreen({super.key, required this.path});

  @override
  State<XlsxEditorScreen> createState() => _XlsxEditorScreenState();
}

class _SheetGrid {
  final String name;
  final List<PlutoColumn> columns;
  final List<PlutoRow> rows;
  PlutoGridStateManager? stateManager;

  _SheetGrid({required this.name, required this.columns, required this.rows});
}

class _XlsxEditorScreenState extends State<XlsxEditorScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  String? _errorMessage;

  xl.Excel? _excel;
  List<_SheetGrid> _sheets = [];
  int _activeSheetIndex = 0;

  String get _fileName => widget.path.split('/').last;

  String get _parentPath {
    final idx = widget.path.lastIndexOf('/');
    return idx <= 0 ? '/' : widget.path.substring(0, idx);
  }

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final excel = xl.Excel.decodeBytes(bytes);
      final sheets = <_SheetGrid>[];

      for (final sheetName in excel.tables.keys) {
        final table = excel.tables[sheetName]!;
        final colCount = table.maxColumns == 0 ? 5 : table.maxColumns;
        final rowCount = table.maxRows;

        final columns = List.generate(
          colCount,
          (c) => PlutoColumn(
            title: _columnLetter(c),
            field: 'col_$c',
            type: PlutoColumnType.text(),
            enableSorting: false,
            enableColumnDrag: false,
            enableContextMenu: false,
          ),
        );

        final rows = List.generate(rowCount, (r) {
          final sourceRow = r < table.rows.length ? table.rows[r] : const [];
          final cells = <String, PlutoCell>{};
          for (var c = 0; c < colCount; c++) {
            final cellData = c < sourceRow.length ? sourceRow[c] : null;
            cells['col_$c'] = PlutoCell(value: _cellValueToString(cellData?.value));
          }
          return PlutoRow(cells: cells);
        });

        sheets.add(_SheetGrid(name: sheetName, columns: columns, rows: rows));
      }

      if (!mounted) return;
      setState(() {
        _excel = excel;
        _sheets = sheets;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // A, B, C, ... Z, AA, AB, ... — penomoran kolom gaya spreadsheet.
  String _columnLetter(int index) {
    var n = index;
    var result = '';
    while (true) {
      result = String.fromCharCode(65 + (n % 26)) + result;
      n = n ~/ 26 - 1;
      if (n < 0) break;
    }
    return result;
  }

  String _cellValueToString(xl.CellValue? value) {
    if (value == null) return '';
    try {
      if (value is xl.TextCellValue) return value.value.toString();
      if (value is xl.IntCellValue) return value.value.toString();
      if (value is xl.DoubleCellValue) return value.value.toString();
      if (value is xl.BoolCellValue) return value.value.toString();
      if (value is xl.FormulaCellValue) return '=${value.formula}';
    } catch (_) {
      // Fallback di bawah kalau ada tipe yang field-nya beda dugaan.
    }
    // Date/Time/DateTime & tipe lain di luar 5 tipe umum di atas —
    // ditampilkan apa adanya lewat toString() bawaan package.
    return value.toString();
  }

  xl.CellValue? _parseCellValue(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final intVal = int.tryParse(trimmed);
    if (intVal != null) return xl.IntCellValue(intVal);
    final doubleVal = double.tryParse(trimmed);
    if (doubleVal != null) return xl.DoubleCellValue(doubleVal);
    if (trimmed.toLowerCase() == 'true') return xl.BoolCellValue(true);
    if (trimmed.toLowerCase() == 'false') return xl.BoolCellValue(false);
    return xl.TextCellValue(trimmed);
  }

  void _onGridChanged(PlutoGridOnChangedEvent event) {
    if (!_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  // ---------------- Tambah Baris / Kolom ----------------

  void _addRow() {
    final sheet = _sheets[_activeSheetIndex];
    sheet.stateManager?.appendNewRows(count: 1);
    setState(() => _hasUnsavedChanges = true);
  }

  void _addColumn() {
    final sheet = _sheets[_activeSheetIndex];
    final manager = sheet.stateManager;
    if (manager == null) return;

    final newIndex = manager.columns.length;
    final newColumn = PlutoColumn(
      title: _columnLetter(newIndex),
      field: 'col_$newIndex',
      type: PlutoColumnType.text(),
      enableSorting: false,
      enableColumnDrag: false,
      enableContextMenu: false,
    );
    manager.insertColumns(newIndex, [newColumn]);
    setState(() => _hasUnsavedChanges = true);
  }

  // ---------------- Save ----------------

  Future<void> _save() async {
    final excel = _excel;
    if (excel == null) return;

    setState(() => _isSaving = true);
    try {
      for (final sheet in _sheets) {
        final manager = sheet.stateManager;
        if (manager == null) continue;

        final table = excel.tables[sheet.name] ?? excel[sheet.name];
        final currentColumns = manager.columns;
        final currentRows = manager.rows;

        for (var r = 0; r < currentRows.length; r++) {
          final row = currentRows[r];
          for (var c = 0; c < currentColumns.length; c++) {
            final field = currentColumns[c].field;
            final text = (row.cells[field]?.value ?? '').toString();
            table.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value =
                _parseCellValue(text);
          }
        }
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Gagal encode file XLSX');
      await File(widget.path).writeAsBytes(Uint8List.fromList(bytes));

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

  // ---------------- Menu More ----------------

  void _handleMenuAction(String value) {
    switch (value) {
      case 'add_row':
        _addRow();
        break;
      case 'add_column':
        _addColumn();
        break;
      case 'save':
        _save();
        break;
    }
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return [
      const PopupMenuItem(value: 'add_row', child: _MenuRow(icon: Icons.table_rows_outlined, label: 'Tambah Baris')),
      const PopupMenuItem(value: 'add_column', child: _MenuRow(icon: Icons.view_column_outlined, label: 'Tambah Kolom')),
      const PopupMenuDivider(height: 8),
      PopupMenuItem(
        value: 'save',
        enabled: !_isSaving,
        child: _MenuRow(icon: Icons.save_outlined, label: 'Save', dimmed: _isSaving),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
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
                      _fileName,
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
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
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
    if (_sheets.isEmpty) {
      return const Center(
        child: Text('File XLSX ini tidak punya sheet', style: TextStyle(color: Colors.white54)),
      );
    }

    return Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: _activeSheetIndex,
            children: [
              for (final sheet in _sheets)
                PlutoGrid(
                  columns: sheet.columns,
                  rows: sheet.rows,
                  onChanged: _onGridChanged,
                  onLoaded: (event) => sheet.stateManager = event.stateManager,
                  configuration: const PlutoGridConfiguration.dark(
                    style: PlutoGridStyleConfig.dark(
                      gridBackgroundColor: _editorBackground,
                      rowColor: _editorBackground,
                      activatedColor: Color(0x330A84FF),
                      activatedBorderColor: _dalxAccent,
                      gridBorderColor: Color(0xFF3A3A3A),
                      borderColor: Color(0xFF3A3A3A),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_sheets.length > 1) _buildSheetTabs(),
      ],
    );
  }

  Widget _buildSheetTabs() {
    return Container(
      height: 44,
      color: _panelBackground,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _sheets.length,
        itemBuilder: (context, index) {
          final isActive = index == _activeSheetIndex;
          return InkWell(
            onTap: () => setState(() => _activeSheetIndex = index),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? _dalxAccent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                _sheets[index].name,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------- Baris menu (icon + label) buat PopupMenuItem ----------------

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool dimmed;

  const _MenuRow({required this.icon, required this.label, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final color = dimmed ? Colors.grey.shade600 : Colors.white;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}
