# android/app/proguard-rules.pro
#
# Aturan R8 buat build release (minifyEnabled true, lihat build.gradle).
# Filosofi di sini: KONSERVATIF — lebih baik under-shrink (ukuran APK
# sedikit lebih besar) daripada over-shrink (crash runtime karena kelas
# yang dipanggil lewat reflection/MethodChannel ke-strip). Kalau ada
# fitur yang crash di APK release padahal jalan normal di debug, cek
# logcat buat "ClassNotFoundException"/"NoSuchMethodError" dulu — itu
# tanda ada kelas yang perlu ditambahin -keep di sini.

# ---------------- Flutter engine & plugin ----------------
# Aturan standar resmi Flutter — MethodChannel, plugin registrant,
# dan embedding engine WAJIB di-keep utuh, karena banyak dipanggil
# lewat reflection dari sisi native (bukan cuma direct call biasa).
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# ---------------- Kode DalX sendiri (native bridge) ----------------
# MainActivity.kt & NativeBridge.kt didaftarkan sebagai MethodChannel
# handler — nggak boleh ke-strip/ke-rename walau kelihatan "nggak
# dipanggil langsung" dari sudut pandang R8 (dipanggil dari sisi Dart
# lewat nama method sebagai string, R8 nggak bisa lacak itu).
-keep class com.dalx.app.** { *; }

# ---------------- video_player / ExoPlayer (Media3) ----------------
# Dependency androidx.media3 (dipakai video_player_android, Fase 3)
# — proyek Media3 sendiri merekomendasikan dontwarn ini di dokumentasi
# resminya karena beberapa fitur opsional (misal decoder eksternal)
# direferensikan tapi nggak selalu ada di classpath.
-dontwarn androidx.media3.**
-keep class androidx.media3.** { *; }

# ---------------- flutter_pdfview ----------------
-keep class com.github.barteksc.** { *; }

# ---------------- Gson (dipakai beberapa plugin buat serialisasi) ----------------
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

# ---------------- Parcelable & enum (pola umum yang sering ke-strip salah) ----------------
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ---------------- Kotlin metadata ----------------
-keep class kotlin.Metadata { *; }
-keepclassmembers class **$WhenMappings {
    <fields>;
}

# ---------------- Commons Compress + XZ (7z) & junrar (RAR) — Fase 8 Pilar #2 ----------------
# Commons Compress punya referensi OPSIONAL ke beberapa logging/codec
# library yang TIDAK kita include (kita nggak butuh logging framework
# apa pun, DalX nggak pakai slf4j secara langsung) — kalau nggak
# di-dontwarn, R8 anggap "missing class" dan build GAGAL walau
# runtime-nya aman (Commons Compress punya fallback kalau library
# opsional ini nggak ketemu di classpath).
-dontwarn org.slf4j.**
# Brotli & Zstd: codec kompresi opsional lain yang bisa direferensikan
# Commons Compress tapi TIDAK kita pakai (DalX cuma butuh 7z/LZMA2,
# sudah tercover xz:1.9). Ditambah preventif biar nggak perlu
# bolak-balik build cuma buat nemuin missing class serupa satu-satu.
-dontwarn org.brotli.dec.**
-dontwarn com.github.luben.zstd.**

# junrar (RAR extract) — dipanggil langsung (bukan lewat
# MethodChannel/reflection kayak com.dalx.app.**), tapi tetap di-keep
# konservatif sesuai filosofi file ini: beberapa versi junrar pakai
# reflection internal buat deteksi multi-volume archive (.part1.rar,
# dst) yang R8 nggak bisa lacak lewat call graph biasa.
-keep class com.github.junrar.** { *; }
-dontwarn com.github.junrar.**

# Commons Compress sendiri: konservatif sama, di-keep utuh biar aman
# dari method/field yang ke-strip salah gara-gara reflection internal
# (mis. deteksi format arsip otomatis lewat ArchiveStreamFactory).
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**

# PdfBox-Android (rotate PDF, Fase 8 Pilar #3) — di-keep konservatif,
# banyak class internal PdfBox dimuat via reflection (font handling,
# COS object model) yang R8 tidak bisa lacak lewat call graph biasa.
-keep class com.tom_roush.pdfbox.** { *; }
-keep class com.tom_roush.fontbox.** { *; }
-dontwarn com.tom_roush.pdfbox.**
-dontwarn com.tom_roush.fontbox.**
-dontwarn com.tom_roush.harmony.**
