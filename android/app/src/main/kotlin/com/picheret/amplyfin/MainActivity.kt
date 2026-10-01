package com.picheret.amplyfin

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.os.StatFs
import android.view.Display
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
        // Ce que la puce vidéo sait décoder, et si l'écran est HDR
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "amplyfin/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "decoders") {
                    try {
                        result.success(decoders())
                    } catch (e: Exception) {
                        result.error("decoders", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    /// Formats lourds (nom Jellyfin → type Android).
    private val videoTypes = mapOf(
        "h264" to "video/avc",
        "hevc" to "video/hevc",
        "av1" to "video/av01",
        "vp9" to "video/x-vnd.on2.vp9",
    )

    /// Définitions essayées, de la plus grande à la plus petite.
    private val sizes = listOf(
        7680 to 4320,
        4096 to 2160,
        3840 to 2160,
        2560 to 1440,
        1920 to 1080,
        1280 to 720,
    )

    private fun decoders(): Map<String, Any> {
        val infos = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter { !it.isEncoder }
        val codecs = mutableMapOf<String, Any>()
        for ((name, type) in videoTypes) {
            // Le meilleur décodeur du format : la puce d'abord, puis la plus
            // grande définition
            var best: Map<String, Any>? = null
            var bestScore = -1
            for (info in infos) {
                if (info.supportedTypes.none { it.equals(type, ignoreCase = true) }) continue
                val caps = try {
                    info.getCapabilitiesForType(type)
                } catch (e: Exception) {
                    continue
                }
                val video = caps.videoCapabilities ?: continue
                val size = sizes.firstOrNull { (w, h) -> video.isSizeSupported(w, h) }
                    ?: (video.supportedWidths.upper to video.supportedHeights.upper)
                val hardware = isHardware(info)
                val score = (if (hardware) 100000 else 0) + size.first
                if (score <= bestScore) continue
                bestScore = score
                best = mapOf(
                    "hardware" to hardware,
                    "maxWidth" to size.first,
                    "maxHeight" to size.second,
                    "tenBit" to caps.profileLevels.any { isTenBit(name, it.profile) },
                )
            }
            if (best != null) codecs[name] = best
        }
        val dolbyVision = infos.any { info ->
            info.supportedTypes.any { it.equals("video/dolby-vision", ignoreCase = true) }
        }
        return mapOf(
            "codecs" to codecs,
            "dolbyVision" to dolbyVision,
            "hdrScreen" to hdrScreen(),
        )
    }

    /// Vrai si le décodeur est la puce vidéo (et pas le processeur).
    private fun isHardware(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return info.isHardwareAccelerated
        }
        val name = info.name.lowercase()
        return !(name.startsWith("omx.google.") || name.startsWith("c2.android.") ||
            name.contains(".sw."))
    }

    /// Vrai si le profil est une version 10 bits du format (valeurs des
    /// constantes MediaCodecInfo.CodecProfileLevel).
    private fun isTenBit(codec: String, profile: Int): Boolean = when (codec) {
        // Main10, Main10HDR10, Main10HDR10Plus
        "hevc" -> profile == 0x2 || profile == 0x1000 || profile == 0x2000
        // Main10, Main10HDR10, Main10HDR10Plus
        "av1" -> profile == 0x2 || profile == 0x1000 || profile == 0x2000
        // Profile2, Profile3 et leurs variantes HDR
        "vp9" -> profile == 0x4 || profile == 0x8 || profile == 0x1000 ||
            profile == 0x2000 || profile == 0x4000 || profile == 0x8000
        // High10
        "h264" -> profile == 0x10
        else -> false
    }

    /// Vrai si l'écran sait afficher le HDR (HDR10, HLG ou Dolby Vision).
    @Suppress("DEPRECATION")
    private fun hdrScreen(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val display: Display = windowManager.defaultDisplay
        val types = display.hdrCapabilities?.supportedHdrTypes ?: return false
        return types.isNotEmpty()
    }
}
