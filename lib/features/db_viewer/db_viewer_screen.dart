// features/db_viewer/db_viewer_screen.dart
//
// Fase 9 — Database Viewer. Baca & TULIS file SQLite (.db/.sqlite/
// .sqlite3/.db3) langsung dari Explorer. Dua tab:
// - Tabel: daftar tabel (chip), browse isi + edit cell inline +
//   select+delete baris + tambah baris baru.
// - Query: SQL bebas (SELECT/INSERT/UPDATE/DELETE/dst), hasil SELECT
//   tampil di grid yang sama, non-SELECT nampilin jumlah baris
//   terpengaruh.
//
// Package: sqlite3 (FFI binding resmi) + sqlite3_flutter_libs (bundle
// native libsqlite3.so per-ABI) — TIDAK butuh native Kotlin custom
// sama sekali, beda dari kasus PPT/Compress/Rotate-PDF (yang sempat
// dicoba lalu dihapus).
//
// BATASAN YANG DISADARI:
// - Row per tabel dibatasi 500 baris pertama (LIMIT 500) — file .db
//   bisa berisi jutaan baris, load semua ke ListView sekaligus bisa
//   bikin app lag/OOM. Query tab TIDAK kena batas ini (user yang
//   nulis query sendiri, tanggung jawab sendiri kalau nulis SELECT
//   tanpa LIMIT ke tabel jutaan baris).
// - Semua operasi baca/tulis SQLite jalan SINKRON di main isolate
//   (batasan sqlite3 FFI — objek Database tidak bisa dikirim antar
//   isolate dengan mudah). Untuk file .db yang wajar (bukan berGB-GB)
//   ini nggak kerasa, tapi disadari sebagai keterbatasan.
// - Kolom identifikasi baris pakai `rowid` bawaan SQLite (built-in di
//   hampir semua tabel kecuali WITHOUT ROWID) — bukan kolom PK
//   deklarasi tabel, supaya tetap jalan walau tabel tidak punya PK
//   eksplisit atau PK-nya komposit.

import 'package:flutter/material.dart';
// `hide Row` WAJIB — package sqlite3 punya class Row sendiri (1 baris
// hasil query) yang namanya BENTROK sama widget Row bawaan Flutter
// (layout horizontal). Kita nggak pernah butuh tipe Row dari sqlite3
// secara eksplisit di file ini (selalu diakses via `row['nama_kolom']`
// dengan inferensi tipe), jadi aman di-hide sepenuhnya.
import 'package:sqlite3/sqlite3.dart' hide Row;

const _dalxAccent = Color(0xFF0A84FF);
const _bgApp = Color(0xFF0D0D0D);
const _bgSurface = Color(0xFF17171A);
const _bgSurface2 = Color(0xFF1E1E22);
const _bgElevated = Color(0xFF232327);
const _borderColor = Color(0x14FFFFFF);
const _borderStrong = Color(0x24FFFFFF);
const _textSecondary = Color(0x9EF2F2F3);
const _textTertiary = Color(0x57F2F2F3);
const _monoFont = 'monospace';
const _rowLimit = 500;

class _ColumnInfo {
  final String name;
  final String type;
  final bool isPrimaryKey;
  const _ColumnInfo({required this.name, required this.type, required this.isPrimaryKey});
}

class DbViewerScreen extends StatefulWidget {
  final String path;
  const DbViewerScreen({super.key, required this.path});

  @override
  State<DbViewerScreen> createState() => _DbViewerScreenState();
}

class _DbViewerScreenState extends State<DbViewerScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Database? _db;
  String? _openError;

  List<String> _tableNames = [];
  String? _currentTable;
  List<_ColumnInfo> _columns = [];
  List<int> _rowIds = [];
  List<List<Object?>> _rows = [];
  final Set<int> _selectedRowIds = {};

  final _queryController = TextEditingController();
  List<_ColumnInfo>? _queryResultColumns;
  List<List<Object?>>? _queryResultRows;
  int? _queryAffectedRows;
  String? _queryError;

  final List<String> _queryHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _openDatabase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _queryController.dispose();
    _db?.dispose();
    super.dispose();
  }

  void _openDatabase() {
    try {
      final db = sqlite3.open(widget.path);
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
          .map((row) => row['name'] as String)
          .toList();
      setState(() {
        _db = db;
        _tableNames = tables;
        _currentTable = tables.isNotEmpty ? tables.first : null;
      });
      if (_currentTable != null) _loadTable(_currentTable!);
    } catch (e) {
      setState(() => _openError = e.toString());
    }
  }

  void _loadTable(String tableName) {
    final db = _db;
    if (db == null) return;
    try {
      final pragma = db.select('PRAGMA table_info(${_quoteIdent(tableName)})');
      final columns = pragma
          .map((r) => _ColumnInfo(
                name: r['name'] as String,
                type: ((r['type'] as String?)?.isEmpty ?? true) ? 'BLOB' : (r['type'] as String),
                isPrimaryKey: (r['pk'] as int) > 0,
              ))
          .toList();

      // rowid bawaan SQLite dipakai sebagai identifier baris yang
      // ANDAL (bukan kolom PK deklarasi tabel) — lihat catatan header
      // file. Alias "_rowid_" biar tidak bentrok kalau tabel kebetulan
      // punya kolom bernama "rowid" sendiri.
      final result = db.select(
        'SELECT rowid AS _rowid_, * FROM ${_quoteIdent(tableName)} LIMIT $_rowLimit',
      );

      final rowIds = <int>[];
      final rows = <List<Object?>>[];
      for (final row in result) {
        rowIds.add(row['_rowid_'] as int);
        rows.add(columns.map((c) => row[c.name]).toList());
      }

      setState(() {
        _currentTable = tableName;
        _columns = columns;
        _rowIds = rowIds;
        _rows = rows;
        _selectedRowIds.clear();
      });
    } catch (e) {
      _showSnack('Gagal baca tabel: $e');
    }
  }

  String _quoteIdent(String ident) => '"${ident.replaceAll('"', '""')}"';

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontSize: 13))),
    );
  }

  void _editCell(int rowIndex, int colIndex, Object? newValue) {
    final db = _db;
    final table = _currentTable;
    if (db == null || table == null) return;
    final rowId = _rowIds[rowIndex];
    final colName = _columns[colIndex].name;
    try {
      db.execute(
        'UPDATE ${_quoteIdent(table)} SET ${_quoteIdent(colName)} = ? WHERE rowid = ?',
        [newValue, rowId],
      );
      setState(() => _rows[rowIndex][colIndex] = newValue);
      _showSnack('Cell diperbarui — langsung tersimpan ke .db');
    } catch (e) {
      _showSnack('Gagal update: $e');
    }
  }

  void _deleteSelected() {
    final db = _db;
    final table = _currentTable;
    if (db == null || table == null || _selectedRowIds.isEmpty) return;
    try {
      for (final rowId in _selectedRowIds) {
        db.execute('DELETE FROM ${_quoteIdent(table)} WHERE rowid = ?', [rowId]);
      }
      final count = _selectedRowIds.length;
      _loadTable(table);
      _showSnack('$count baris dihapus');
    } catch (e) {
      _showSnack('Gagal hapus: $e');
    }
  }

  void _addRow() {
    final db = _db;
    final table = _currentTable;
    if (db == null || table == null) return;
    try {
      // Insert semua kolom sebagai NULL — kalau ada constraint NOT
      // NULL tanpa default, ini bakal gagal & errornya ditampilkan
      // apa adanya (user power-user, wajar liat error SQLite asli
      // daripada pesan yang di-dumbing-down).
      final colNames = _columns.map((c) => _quoteIdent(c.name)).join(', ');
      final placeholders = List.filled(_columns.length, '?').join(', ');
      db.execute(
        'INSERT INTO ${_quoteIdent(table)} ($colNames) VALUES ($placeholders)',
        List<Object?>.filled(_columns.length, null),
      );
      _loadTable(table);
      _showSnack('Baris baru ditambahkan');
    } catch (e) {
      _showSnack('Gagal tambah baris: $e');
    }
  }

  void _runQuery() {
    final db = _db;
    final sql = _queryController.text.trim();
    if (db == null || sql.isEmpty) return;
    setState(() {
      _queryError = null;
      _queryResultColumns = null;
      _queryResultRows = null;
      _queryAffectedRows = null;
    });
    try {
      final result = db.select(sql);
      if (result.columnNames.isNotEmpty) {
        final cols = result.columnNames
            .map((name) => _ColumnInfo(name: name, type: '', isPrimaryKey: false))
            .toList();
        final rows = result.map((row) => result.columnNames.map((c) => row[c]).toList()).toList();
        setState(() {
          _queryResultColumns = cols;
          _queryResultRows = rows;
        });
      } else {
        setState(() => _queryAffectedRows = db.updatedRows);
        // Query DDL/DML bisa ngubah struktur (CREATE/DROP/ALTER TABLE)
        // — refresh daftar tabel biar sinkron.
        _refreshTableList();
      }
      if (!_queryHistory.contains(sql)) {
        _queryHistory.insert(0, sql);
        if (_queryHistory.length > 8) _queryHistory.removeLast();
      }
    } catch (e) {
      setState(() => _queryError = e.toString());
    }
  }

  void _refreshTableList() {
    final db = _db;
    if (db == null) return;
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        .map((row) => row['name'] as String)
        .toList();
    setState(() => _tableNames = tables);
  }

  String get _fileName => widget.path.split('/').last;

  @override
  Widget build(BuildContext context) {
    if (_openError != null) {
      return Scaffold(
        backgroundColor: _bgApp,
        appBar: AppBar(backgroundColor: _bgApp, title: Text(_fileName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Gagal membuka database:\n$_openError',
              style: const TextStyle(color: _textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_db == null) {
      return const Scaffold(
        backgroundColor: _bgApp,
        body: Center(child: CircularProgressIndicator(color: _dalxAccent)),
      );
    }

    return Scaffold(
      backgroundColor: _bgApp,
      appBar: AppBar(
        backgroundColor: _bgApp,
        elevation: 0,
        titleSpacing: 0,
        title: Text(_fileName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _dalxAccent,
          indicatorWeight: 2.5,
          labelColor: Colors.white,
          unselectedLabelColor: _textTertiary,
          labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Tabel'), Tab(text: 'Query')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildTablesTab(), _buildQueryTab()],
      ),
    );
  }

  Widget _buildTablesTab() {
    if (_tableNames.isEmpty) {
      return const Center(
        child: Text('Tidak ada tabel di database ini', style: TextStyle(color: _textTertiary)),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            if (_selectedRowIds.isNotEmpty) _buildSelectionBar(),
            _buildChipRow(),
            Expanded(
              child: _DataGrid(
                columns: _columns,
                rows: _rows,
                selectable: true,
                selectedIndices: _rowIds
                    .asMap()
                    .entries
                    .where((e) => _selectedRowIds.contains(e.value))
                    .map((e) => e.key)
                    .toSet(),
                onCellCommit: _editCell,
                onRowLongPress: (i) => setState(() => _selectedRowIds.add(_rowIds[i])),
                onRowTapWhileSelecting: (i) => setState(() {
                  final id = _rowIds[i];
                  if (_selectedRowIds.contains(id)) {
                    _selectedRowIds.remove(id);
                  } else {
                    _selectedRowIds.add(id);
                  }
                }),
                isSelecting: _selectedRowIds.isNotEmpty,
              ),
            ),
          ],
        ),
        // FAB tambah baris — disembunyikan selagi mode pilih aktif,
        // biar nggak dobel-arti sama tombol Hapus di selection bar.
        if (_selectedRowIds.isEmpty)
          Positioned(
            right: 16,
            bottom: 20,
            child: FloatingActionButton(
              backgroundColor: _dalxAccent,
              onPressed: _addRow,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildSelectionBar() {
    return Container(
      color: _bgSurface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: _textSecondary, size: 20),
            onPressed: () => setState(() => _selectedRowIds.clear()),
          ),
          Expanded(
            child: Text('${_selectedRowIds.length} dipilih',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 21),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Hapus baris?'),
                  content: Text('${_selectedRowIds.length} baris akan dihapus permanen dari database.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Hapus', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) _deleteSelected();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChipRow() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _tableNames.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final name = _tableNames[i];
          final isActive = name == _currentTable;
          return GestureDetector(
            onTap: () => _loadTable(name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? _dalxAccent.withOpacity(0.14) : _bgSurface2,
                border: Border.all(color: isActive ? _dalxAccent.withOpacity(0.3) : _borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: _monoFont,
                  fontSize: 12,
                  color: isActive ? _dalxAccent : _textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQueryTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_queryHistory.isNotEmpty)
            SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _queryHistory.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => setState(() => _queryController.text = _queryHistory[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _bgSurface2,
                      border: Border.all(color: _borderColor),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      _queryHistory[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: _monoFont, fontSize: 11, color: _textTertiary),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: _bgSurface2,
              border: Border.all(color: _borderStrong),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _queryController,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(fontFamily: _monoFont, fontSize: 12.5, color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
                hintText: 'SELECT * FROM nama_tabel\nWHERE ...;',
                hintStyle: TextStyle(fontFamily: _monoFont, color: _textTertiary),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_queryAffectedRows != null)
                Text('${_queryAffectedRows} baris terpengaruh',
                    style: const TextStyle(fontSize: 11, color: _textTertiary)),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _dalxAccent),
                onPressed: _runQuery,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Jalankan'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: _buildQueryResult()),
        ],
      ),
    );
  }

  Widget _buildQueryResult() {
    if (_queryError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(_queryError!, style: const TextStyle(color: Colors.redAccent, fontFamily: _monoFont, fontSize: 12)),
      );
    }
    if (_queryResultColumns == null) {
      return Container(
        decoration: BoxDecoration(border: Border.all(color: _borderColor), borderRadius: BorderRadius.circular(12)),
        child: const Center(
          child: Text('Jalankan query buat lihat hasilnya di sini',
              style: TextStyle(color: _textTertiary, fontSize: 12.5)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(border: Border.all(color: _borderColor), borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: _DataGrid(
        columns: _queryResultColumns!,
        rows: _queryResultRows!,
        selectable: false,
        selectedIndices: const {},
        onCellCommit: null,
        onRowLongPress: null,
        onRowTapWhileSelecting: null,
        isSelecting: false,
      ),
    );
  }
}

/// Grid data reusable — dipakai tab Tabel (bisa edit+select) dan hasil
/// tab Query (read-only). Sticky header (nempel pas scroll vertikal),
/// horizontal+vertical scroll independen dari header.
class _DataGrid extends StatelessWidget {
  final List<_ColumnInfo> columns;
  final List<List<Object?>> rows;
  final bool selectable;
  final Set<int> selectedIndices;
  final void Function(int rowIndex, int colIndex, Object? newValue)? onCellCommit;
  final void Function(int rowIndex)? onRowLongPress;
  final void Function(int rowIndex)? onRowTapWhileSelecting;
  final bool isSelecting;

  const _DataGrid({
    required this.columns,
    required this.rows,
    required this.selectable,
    required this.selectedIndices,
    required this.onCellCommit,
    required this.onRowLongPress,
    required this.onRowTapWhileSelecting,
    required this.isSelecting,
  });

  static const _colWidth = 130.0;
  static const _checkboxColWidth = 40.0;

  @override
  Widget build(BuildContext context) {
    final totalWidth = _colWidth * columns.length + (selectable ? _checkboxColWidth : 0);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          children: [
            _buildHeaderRow(),
            const Divider(height: 1, color: _borderStrong),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('Tabel kosong', style: TextStyle(color: _textTertiary, fontSize: 12.5)))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, rowIndex) => _buildRow(context, rowIndex),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      color: const Color(0xFF131316),
      child: Row(
        children: [
          if (selectable) const SizedBox(width: _checkboxColWidth),
          ...columns.map((col) => SizedBox(
                width: _colWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 9, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (col.isPrimaryKey)
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: const BoxDecoration(color: _dalxAccent, shape: BoxShape.circle),
                            ),
                          Flexible(
                            child: Text(
                              col.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      if (col.type.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.only(top: 5),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: _borderStrong, width: 1)),
                          ),
                          child: Text(
                            col.type,
                            style: const TextStyle(fontSize: 9, letterSpacing: 0.5, color: _textTertiary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, int rowIndex) {
    final isSelected = selectedIndices.contains(rowIndex);
    final row = rows[rowIndex];
    return GestureDetector(
      onLongPress: selectable ? () => onRowLongPress?.call(rowIndex) : null,
      child: Container(
        color: isSelected
            ? _dalxAccent.withOpacity(0.14)
            : (rowIndex.isEven ? Colors.transparent : Colors.white.withOpacity(0.014)),
        child: Row(
          children: [
            if (selectable)
              SizedBox(
                width: _checkboxColWidth,
                child: Center(
                  child: GestureDetector(
                    onTap: () => onRowTapWhileSelecting?.call(rowIndex),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: isSelected ? _dalxAccent : Colors.transparent,
                        border: Border.all(color: isSelected ? _dalxAccent : _borderStrong, width: 1.5),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                    ),
                  ),
                ),
              ),
            ...row.asMap().entries.map((entry) {
              final colIndex = entry.key;
              final value = entry.value;
              final isPk = columns[colIndex].isPrimaryKey;
              return SizedBox(
                width: _colWidth,
                child: _EditableCell(
                  value: value,
                  bold: isPk,
                  editable: onCellCommit != null && !isSelecting,
                  onCommit: (v) => onCellCommit?.call(rowIndex, colIndex, v),
                  onTapWhileSelecting: isSelecting ? () => onRowTapWhileSelecting?.call(rowIndex) : null,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _EditableCell extends StatefulWidget {
  final Object? value;
  final bool bold;
  final bool editable;
  final ValueChanged<Object?> onCommit;
  final VoidCallback? onTapWhileSelecting;

  const _EditableCell({
    required this.value,
    required this.bold,
    required this.editable,
    required this.onCommit,
    required this.onTapWhileSelecting,
  });

  @override
  State<_EditableCell> createState() => _EditableCellState();
}

class _EditableCellState extends State<_EditableCell> {
  bool _editing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant _EditableCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing) _controller.text = widget.value?.toString() ?? '';
  }

  void _commit() {
    final text = _controller.text;
    setState(() => _editing = false);
    widget.onCommit(text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(fontFamily: _monoFont, fontSize: 12.5, color: Colors.white),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            filled: true,
            fillColor: _bgElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: _dalxAccent, width: 1.5),
            ),
          ),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
        ),
      );
    }

    final isNull = widget.value == null;
    return InkWell(
      onTap: widget.onTapWhileSelecting ?? (widget.editable ? () => setState(() => _editing = true) : null),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Text(
          isNull ? 'NULL' : widget.value.toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: _monoFont,
            fontSize: 12.5,
            fontStyle: isNull ? FontStyle.italic : FontStyle.normal,
            fontWeight: widget.bold ? FontWeight.w600 : FontWeight.normal,
            color: isNull ? _textTertiary : (widget.bold ? Colors.white : _textSecondary),
          ),
        ),
      ),
    );
  }
}
