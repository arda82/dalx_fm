// core/localization/app_strings.dart
//
// Infrastruktur terjemahan ID/EN — pure Dart, BUKAN flutter
// gen-l10n/.arb (itu nambah code-gen step ke CI, riskan nyangkut
// kayak kejadian AGP kemarin). Cukup satu class `AppStrings` berisi
// getter per string, dipilih ID/EN lewat `_t(id, en)`.
//
// Diakses lewat `AppStrings.of(context)` di MANA PUN (StatelessWidget
// biasa maupun ConsumerWidget) — pakai mekanisme Localizations bawaan
// Flutter (LocalizationsDelegate), bukan Riverpod, supaya widget kecil
// non-Consumer (_MenuRow, _FileListTile, dst) juga bisa akses tanpa
// perlu di-refactor jadi ConsumerWidget semua.
//
// Locale aktif (AppLocale) sendiri persist lewat Riverpod di
// core/settings/app_settings.dart (localeProvider) — DalXApp
// (main.dart) watch provider itu dan oper ke `MaterialApp.locale`,
// baru dari situ Localizations/AppStrings.of(context) ikut berubah.
//
// Nambah string baru: tambah 1 getter di sini, dipakai di
// widget manapun cukup `AppStrings.of(context).namaGetter`. Jangan
// hardcode Text('...') Bahasa Indonesia langsung di layar baru lagi.

import 'package:flutter/material.dart';

enum AppLocale { id, en }

class AppStrings {
  final AppLocale locale;
  const AppStrings(this.locale);

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ?? const AppStrings(AppLocale.id);
  }

  bool get _isEn => locale == AppLocale.en;
  String _t(String id, String en) => _isEn ? en : id;

  // ---------------- Generic / dipakai di banyak tempat ----------------
  String get cancel => _t('Batal', 'Cancel');
  String get save => _t('Simpan', 'Save');
  String get create => _t('Buat', 'Create');
  String get delete => _t('Hapus', 'Delete');
  String get rename => _t('Rename', 'Rename');
  String get share => _t('Share', 'Share');
  String get settings => _t('Settings', 'Settings');
  String get name => _t('Nama', 'Name');
  String get date => _t('Tanggal', 'Date');
  String get size => _t('Ukuran', 'Size');
  String get folder => _t('Folder', 'Folder');
  String get file => _t('File', 'File');

  // ---------------- main.dart — Permission Gate ----------------
  String get permissionTitle => _t('DalX butuh izin akses penyimpanan', 'DalX needs storage access permission');
  String get permissionBody => _t(
        'Untuk mengelola semua file kamu, termasuk file tersembunyi, '
        'DalX perlu izin akses penyimpanan penuh.',
        'To manage all your files, including hidden files, DalX needs '
        'full storage access permission.',
      );
  String get permissionGrantButton => _t('Berikan Izin', 'Grant Permission');
  String permissionErrorDetail(String error) => _t('Detail error: $error', 'Error detail: $error');

  // ---------------- Explorer — Toolbar & AppBar ----------------
  String get appName => 'DalX';
  String get pickFileTitle => _t('Pilih File', 'Pick File');
  String selectedCount(int count) => _t('$count dipilih', '$count selected');
  String get emptyFolder => _t('Folder ini kosong', 'This folder is empty');
  String errorOccurred(String error) => _t('Terjadi kesalahan: $error', 'An error occurred: $error');
  String get noResults => _t('Tidak ada hasil', 'No results');

  // ---------------- Explorer — Action Mode Menu ----------------
  String get fileInfo => _t('File Info', 'File Info');
  String get openWith => _t('Open With', 'Open With');
  String get compress => _t('Compress', 'Compress');
  String get extract => _t('Extract', 'Extract');
  String get addToFavorites => _t('Tambah Favorit', 'Add to Favorites');
  String get removeFromFavorites => _t('Hapus Favorit', 'Remove from Favorites');
  String openWithFailed(String error) => _t('Gagal membuka Open With: $error', 'Failed to open With: $error');
  String shareFailed(String error) => _t('Gagal membuka Share: $error', 'Failed to open Share: $error');
  String sendFileFailed(String error) => _t('Gagal mengirim file: $error', 'Failed to send file: $error');

  // ---------------- Explorer — Compress/Extract Dialog ----------------
  String get compressDialogZipNameLabel => _t('Nama file ZIP', 'ZIP file name');
  String get extractDialogHere => _t('Di sini', 'Here');
  String get extractDialogHereSubtitle =>
      _t('Folder tempat file ZIP ini berada', 'The folder where this ZIP file is located');
  String get extractDialogPick => _t('Pilih', 'Choose');
  String get extractDialogPickSubtitle => _t('Pilih folder tujuan sendiri', 'Choose your own destination folder');

  // ---------------- Explorer — Delete/Rename Dialog ----------------
  String get deleteConfirmTitle => _t('Hapus item?', 'Delete items?');
  String deleteConfirmBody(int count) => _t(
        '$count item akan dihapus. Tindakan ini tidak bisa dibatalkan.',
        '$count item(s) will be deleted. This action cannot be undone.',
      );
  String get renameDialogTitle => _t('Rename', 'Rename');

  // ---------------- Explorer — Clipboard Bar & Conflict Dialog ----------------
  String get clipboardCancel => _t('Batal', 'Cancel');
  String get clipboardPaste => _t('Tempel', 'Paste');
  String get conflictDialogTitle => _t('Nama sudah ada', 'Name already exists');
  String conflictDialogBody(int count, String preview) => _t(
        '$count item sudah ada di folder ini: $preview.\n\nPilih tindakan untuk item yang bentrok:',
        '$count item(s) already exist in this folder: $preview.\n\nChoose an action for the conflicting items:',
      );
  String conflictAndMore(int count) => _t('+$count lainnya', '+$count more');
  String get conflictSkip => _t('Lewati', 'Skip');
  String get conflictOverwrite => _t('Timpa', 'Overwrite');
  String get conflictRenameAuto => _t('Ganti Nama Otomatis', 'Auto Rename');

  // ---------------- Explorer — Install APK Dialog ----------------
  String get installPermissionTitle => _t('Izin diperlukan', 'Permission required');
  String get installPermissionBody =>
      _t('DalX butuh izin install app dari sumber tidak dikenal.', 'DalX needs permission to install apps from unknown sources.');
  String get openSettingsButton => _t('Buka Settings', 'Open Settings');

  // ---------------- Explorer — Restricted Android/data Notice ----------------
  String get restrictedFolderTitle => _t('Isi folder ini dibatasi sistem Android', 'This folder\'s contents are restricted by Android');
  String get restrictedFolderBody => _t(
        'Sejak Android 11, tidak ada aplikasi (termasuk file manager '
        'lain) yang bisa membuka isi folder ini tanpa akses root. Ini '
        'bukan masalah pada DalX.',
        'Since Android 11, no app (including other file managers) can '
        'access this folder\'s contents without root access. This is '
        'not an issue with DalX.',
      );

  // ---------------- Explorer — More Menu ----------------
  String get newFolder => _t('Folder Baru', 'New Folder');
  String get newFile => _t('File Baru', 'New File');
  String get newFolderNameHint => _t('Nama folder', 'Folder name');
  String get newFileNameHint => _t('Nama file (mis. catatan.txt)', 'File name (e.g. notes.txt)');
  String get hideHiddenFiles => _t('Sembunyikan Tersembunyi', 'Hide Hidden Files');
  String get showHiddenFiles => _t('Tampilkan Tersembunyi', 'Show Hidden Files');
  String get listView => _t('Tampilan List', 'List View');
  String get gridView => _t('Tampilan Grid', 'Grid View');
  String get sort => _t('Urutkan', 'Sort');

  // ---------------- File Info Sheet ----------------
  String get infoLocation => _t('Lokasi', 'Location');
  String get infoSize => _t('Ukuran', 'Size');
  String get infoModified => _t('Diubah', 'Modified');
  String get infoMimeType => _t('Tipe MIME', 'MIME Type');
  String get infoPermissions => _t('Izin', 'Permissions');
  List<String> get monthAbbreviations => _isEn
      ? const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
      : const ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

  // ---------------- Task Queue ----------------
  String get taskQueueTitle => _t('Task Queue', 'Task Queue');
  String get clearCompleted => _t('Hapus selesai', 'Clear completed');
  String get noRunningTasks => _t('Tidak ada task berjalan', 'No running tasks');
  String get taskPaused => _t('Dijeda', 'Paused');
  String andMore(int count) => _t('+$count lainnya', '+$count more');
  String get taskCopy => _t('Menyalin', 'Copying');
  String get taskMove => _t('Memindahkan', 'Moving');
  String get taskDelete => _t('Menghapus', 'Deleting');
  String get taskCompress => _t('Mengompres', 'Compressing');
  String get taskExtract => _t('Mengekstrak', 'Extracting');

  // ---------------- App Drawer ----------------
  String get drawerHome => _t('Layar Awal', 'Home');
  String get drawerInternalStorage => _t('Internal Storage', 'Internal Storage');
  String get drawerSdCard => _t('SD Card', 'SD Card');
  String get drawerUsbOtg => _t('USB OTG', 'USB OTG');
  String get drawerFavorites => _t('Favorites', 'Favorites');
  String get drawerTaskQueue => _t('Task Queue', 'Task Queue');
  String get drawerClearCache => _t('Bersihkan Cache', 'Clear Cache');
  String get drawerSettings => _t('Settings', 'Settings');
  String get drawerAbout => _t('About', 'About');
  String get drawerTagline => _t('Explore · Find · Manage', 'Explore · Find · Manage');
  String notMounted(String label) => _t('Tidak ada $label terpasang', 'No $label mounted');
  String get cacheClearedTitle => _t('Cache dibersihkan', 'Cache cleared');
  String cacheClearedBody(String size) => _t('$size berhasil dibebaskan', '$size freed up');
  String get cacheClearConfirmTitle => _t('Bersihkan Cache?', 'Clear Cache?');
  String cacheClearConfirmBody(String size) => _t(
        'Ini akan menghapus $size file cache sementara DalX. File asli '
        'kamu TIDAK terpengaruh.',
        'This will delete $size of DalX\'s temporary cache files. Your '
        'original files are NOT affected.',
      );
  String get cacheEmpty => _t('Cache sudah kosong', 'Cache is already empty');

  // ---------------- Settings ----------------
  String get settingsSectionAppearance => _t('Tampilan Aplikasi', 'App Appearance');
  String get settingsSectionExplorer => _t('Explorer', 'Explorer');
  String get settingsSectionAbout => _t('Tentang', 'About');
  String get settingsTheme => _t('Theme', 'Theme');
  String get settingsThemeDark => _t('Gelap', 'Dark');
  String get settingsThemeLight => _t('Terang', 'Light');
  String get settingsThemeSystem => _t('Ikuti Sistem', 'Follow System');
  String get settingsLanguage => _t('Language', 'Language');
  String get settingsLanguageId => 'Bahasa Indonesia';
  String get settingsLanguageEn => 'English';
  String get settingsDefaultView => _t('Tampilan Default', 'Default View');
  String get settingsDefaultSort => _t('Urutan Default', 'Default Sort');
  String get settingsHiddenDefault => _t('File Tersembunyi Default', 'Hidden Files Default');
  String get settingsHiddenDefaultOn => _t('Tampilkan', 'Show');
  String get settingsHiddenDefaultOff => _t('Sembunyikan', 'Hide');
  String get settingsFontSize => _t('Ukuran Font', 'Font Size');
  String get settingsFontSizeSmall => _t('Kecil', 'Small');
  String get settingsFontSizeNormal => _t('Normal', 'Normal');
  String get settingsFontSizeLarge => _t('Besar', 'Large');
  String get settingsFontSizeExtraLarge => _t('Sangat Besar', 'Extra Large');
  String get settingsHomePath => _t('Layar Awal', 'Home Screen');
  String get settingsHomePathDefault => _t('Storage Overview (default)', 'Storage Overview (default)');
  String get settingsHomePathChoose => _t('Pilih folder lain', 'Choose another folder');
  String get settingsHomePathReset => _t('Kembalikan ke default', 'Reset to default');
  String get settingsRootMode => _t('Root Mode', 'Root Mode');
  String get settingsRootModeOnDesc => _t(
        'Aktif — di ujung folder, tombol back naik terus sampai filesystem root (/)',
        'On — at the end of a folder, back keeps going up to the filesystem root (/)',
      );
  String get settingsRootModeOffDesc => _t(
        'Nonaktif — di ujung folder, tombol back kembali ke Layar Awal',
        'Off — at the end of a folder, back returns to Home',
      );
  String get settingsAppVersion => _t('Versi Aplikasi', 'App Version');
  String get settingsLicense => _t('Lisensi', 'License');
  String get sortByName => _t('Nama', 'Name');
  String get sortByDate => _t('Tanggal', 'Date');
  String get sortByDateNewest => _t('Tanggal (Baru ke Lama)', 'Date (Newest first)');
  String get sortByDateOldest => _t('Tanggal (Lama ke Baru)', 'Date (Oldest first)');
  String get sortBySize => _t('Ukuran', 'Size');
}

/// Delegate resmi Flutter buat AppStrings — didaftarkan di
/// MaterialApp.localizationsDelegates (main.dart), bareng
/// GlobalMaterialLocalizations.delegate & GlobalWidgetsLocalizations.
/// delegate supaya widget bawaan Flutter (DatePicker dll, kalau nanti
/// dipakai) ikut ngikut locale yang sama.
class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => ['id', 'en'].contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) async {
    return AppStrings(locale.languageCode == 'en' ? AppLocale.en : AppLocale.id);
  }

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}
