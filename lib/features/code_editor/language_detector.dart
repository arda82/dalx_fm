// features/code_editor/language_detector.dart
//
// Fase 4 — Code Editor: mapping ekstensi file ke rule syntax
// highlighting re_highlight. Daftar bahasa sengaja dibatasi ke yang
// paling umum dipakai developer (bukan semua ~100 bahasa yang
// didukung re_highlight) supaya jumlah import tetap terkendali —
// tambah baris baru di sini kalau butuh bahasa lain.
//
// CATATAN VERIFIKASI: nama file di package:re_highlight/languages/
// mengikuti persis nama identifier highlight.js (re_highlight adalah
// port 1:1 dari highlight.js). 'dart.dart' dan 'python.dart' sudah
// dikonfirmasi langsung dari contoh resmi. Sisanya (java, kotlin, c,
// cpp, javascript, typescript, json, yaml, xml, css, markdown, bash,
// sql, go, rust, swift, php, ruby) mengikuti pola yang sama persis
// dengan nama file highlight.js aslinya — kalau ternyata ada nama
// yang meleset saat `flutter pub get`/build, tinggal hapus baris
// importnya (fallback: file tetap bisa dibuka di editor, cuma tanpa
// warna syntax untuk bahasa itu).

import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/ruby.dart';

/// Pasangan id bahasa (dipakai sebagai key di CodeHighlightTheme) dan
/// rule mode-nya. Tipe `mode` sengaja dynamic (bukan diketik `Mode`
/// eksplisit) supaya file ini tidak perlu import langsung tipe `Mode`
/// dari re_highlight — cukup andalkan inferensi tipe dari nilai
/// `langXxx` yang diimpor di atas.
class CodeLanguage {
  final String id;
  final dynamic mode;
  const CodeLanguage(this.id, this.mode);
}

/// Cari bahasa yang cocok untuk ekstensi file (huruf kecil, tanpa
/// titik — sama seperti FileItem.extension). Null kalau tidak ada
/// yang cocok (editor tetap bisa dipakai, cuma tanpa syntax color).
CodeLanguage? languageForExtension(String ext) {
  switch (ext) {
    case 'dart':
      return CodeLanguage('dart', langDart);
    case 'py':
      return CodeLanguage('python', langPython);
    case 'java':
      return CodeLanguage('java', langJava);
    case 'kt':
    case 'kts':
      return CodeLanguage('kotlin', langKotlin);
    case 'c':
    case 'h':
      return CodeLanguage('c', langC);
    case 'cpp':
    case 'cc':
    case 'hpp':
    case 'cxx':
      return CodeLanguage('cpp', langCpp);
    case 'js':
      return CodeLanguage('javascript', langJavascript);
    case 'ts':
      return CodeLanguage('typescript', langTypescript);
    case 'json':
      return CodeLanguage('json', langJson);
    case 'yaml':
    case 'yml':
      return CodeLanguage('yaml', langYaml);
    case 'xml':
    case 'html':
    case 'htm':
      return CodeLanguage('xml', langXml);
    case 'css':
      return CodeLanguage('css', langCss);
    case 'md':
    case 'markdown':
      return CodeLanguage('markdown', langMarkdown);
    case 'sh':
    case 'bash':
      return CodeLanguage('bash', langBash);
    case 'sql':
      return CodeLanguage('sql', langSql);
    case 'go':
      return CodeLanguage('go', langGo);
    case 'rs':
      return CodeLanguage('rust', langRust);
    case 'swift':
      return CodeLanguage('swift', langSwift);
    case 'php':
      return CodeLanguage('php', langPhp);
    case 'rb':
      return CodeLanguage('ruby', langRuby);
    default:
      return null;
  }
}

/// True kalau ekstensi ini file HTML — dipakai code_editor_screen.dart
/// buat nentuin kapan tombol "Preview" (render WebView) ditampilkan.
///
/// Sengaja fungsi terpisah dari languageForExtension, BUKAN dicek lewat
/// `language.id == 'xml'` — HTML dipetakan ke rule syntax 'xml' di atas
/// (baris case 'xml'/'html'/'htm'), jadi kalau dicek dari id, file .xml
/// biasa ikut ke-anggap HTML dan preview-nya bakal salah render.
bool isHtmlExtension(String ext) {
  return ext == 'html' || ext == 'htm';
}

/// Nama binary interpreter di Termux (`$PREFIX/bin/<nama>`) buat
/// ekstensi file ini. Null = bahasa ini gak ada interpreter yang
/// masuk akal dijalanin lewat Termux (mis. .json, .md, .txt).
///
/// Dipakai code_editor_screen.dart buat nentuin kapan menu "Run di
/// Termux" ditampilkan — user tetap yang tanggung jawab pastiin
/// interpreter-nya beneran ke-install (`pkg install python`, dst) di
/// Termux miliknya; DalX gak ngecek itu.
String? interpreterCommandFor(String ext) {
  switch (ext) {
    case 'py':
      return 'python3';
    case 'js':
      return 'node';
    case 'sh':
      return 'bash';
    case 'rb':
      return 'ruby';
    case 'php':
      return 'php';
    case 'lua':
      return 'lua';
    default:
      return null;
  }
}
