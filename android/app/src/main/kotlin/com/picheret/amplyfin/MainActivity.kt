package com.picheret.amplyfin

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Place libre et totale du stockage du téléphone (écran Téléchargements)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "amplyfin/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "space") {
                    val stat = StatFs(filesDir.absolutePath)
                    result.success(mapOf("free" to stat.availableBytes, "total" to stat.totalBytes))
                } else {
                    result.notImplemented()
                }
            }
    }
}
