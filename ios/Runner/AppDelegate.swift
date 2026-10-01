import AVFoundation
import CoreMedia
import Flutter
import UIKit
import VideoToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Place libre et totale du téléphone (écran Téléchargements)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AmplyfinStorage") {
      let channel = FlutterMethodChannel(
        name: "amplyfin/storage", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "space" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [
          .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ])
        // Même mesure que les Réglages : place disponible pour les choses importantes
        let free: Int64 = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let total: Int = values?.volumeTotalCapacity ?? 0
        result(["free": NSNumber(value: free), "total": NSNumber(value: total)])
      }
    }

    // Ce que la puce vidéo sait décoder, et si l'écran est HDR
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AmplyfinDevice") {
      let channel = FlutterMethodChannel(
        name: "amplyfin/device", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "decoders" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(AppDelegate.decoders())
      }
    }
  }

  /// Formats décodés par la puce. iOS ne donne pas la définition maximum :
  /// toutes les puces qui décodent ces formats vont jusqu'en 4K, et lisent
  /// la HEVC et l'AV1 en 10 bits.
  static func decoders() -> [String: Any] {
    // Codes à 4 lettres des formats ('avc1', 'hvc1', 'av01', 'vp09', 'dvh1')
    let h264: CMVideoCodecType = 0x6176_6331
    let hevc: CMVideoCodecType = 0x6876_6331
    let av1: CMVideoCodecType = 0x6176_3031
    let vp9: CMVideoCodecType = 0x7670_3039
    let dolbyVision: CMVideoCodecType = 0x6476_6831

    func codec(_ type: CMVideoCodecType, tenBit: Bool) -> [String: Any] {
      let hardware = VTIsHardwareDecodeSupported(type)
      return [
        "hardware": hardware,
        "maxWidth": 3840,
        "maxHeight": 2160,
        "tenBit": hardware && tenBit,
      ]
    }

    return [
      "codecs": [
        "h264": codec(h264, tenBit: false),
        "hevc": codec(hevc, tenBit: true),
        "av1": codec(av1, tenBit: true),
        "vp9": codec(vp9, tenBit: true),
      ],
      "dolbyVision": VTIsHardwareDecodeSupported(dolbyVision),
      "hdrScreen": AVPlayer.eligibleForHDRPlayback,
    ]
  }
}
