package com.dalx.app

import io.flutter.embedding.android.FlutterActivity

// MainActivity — jembatan antara sistem Android dan Flutter engine.
// Ini file WAJIB ada untuk app Flutter apa pun karena
// AndroidManifest.xml mereferensikan android:name=".MainActivity"
// sebagai entry point saat app diluncurkan. Tanpa file ini, sistem
// Android tidak menemukan class Activity yang direferensikan dan
// app crash instan saat dibuka.
class MainActivity : FlutterActivity()
