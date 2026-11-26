import AVFoundation
import Cocoa
import CoreMedia
import FlutterMacOS
import VideoToolbox

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  /// Canal du plein écran (lib/services/app_window.dart).
  private var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Taille minimale, comme sur PC : en dessous, la mise en page se casse
    self.contentMinSize = NSSize(width: 720, height: 480)
    self.title = "Amplyfin"
    self.delegate = self

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerChannels(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func registerChannels(_ messenger: FlutterBinaryMessenger) {
    // Plein écran du lecteur (vrai plein écran du Mac, avec son animation)
    let window = FlutterMethodChannel(name: "amplyfin/window", binaryMessenger: messenger)
    window.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "setFullScreen":
        guard let wanted = call.arguments as? Bool else {
          return result(FlutterError(code: "argument", message: "Booléen attendu", details: nil))
        }
        if wanted != self.isFullScreen { self.toggleFullScreen(nil) }
        result(nil)
      case "isFullScreen":
        result(self.isFullScreen)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    windowChannel = window

    // Place libre et totale du disque (écran Téléchargements)
    let storage = FlutterMethodChannel(name: "amplyfin/storage", binaryMessenger: messenger)
    storage.setMethodCallHandler { call, result in
      guard call.method == "space" else { return result(FlutterMethodNotImplemented) }
      let home = URL(fileURLWithPath: NSHomeDirectory())
      let values = try? home.resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
      ])
      // Même mesure que les Réglages du Mac
      let free: Int64 = values?.volumeAvailableCapacityForImportantUsage ?? 0
      let total: Int = values?.volumeTotalCapacity ?? 0
      result(["free": NSNumber(value: free), "total": NSNumber(value: total)])
    }

    // Ce que la puce vidéo sait décoder, et si l'écran est HDR
    let device = FlutterMethodChannel(name: "amplyfin/device", binaryMessenger: messenger)
    device.setMethodCallHandler { call, result in
      guard call.method == "decoders" else { return result(FlutterMethodNotImplemented) }
      result(MainFlutterWindow.decoders())
    }
  }

  private var isFullScreen: Bool { styleMask.contains(.fullScreen) }

  // Plein écran changé par le Mac lui-même (bouton vert, Échap, ⌃⌘F) :
  // prévient l'appli pour que le bouton du lecteur suive
  func windowDidEnterFullScreen(_ notification: Notification) {
    windowChannel?.invokeMethod("fullScreenChanged", arguments: true)
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    windowChannel?.invokeMethod("fullScreenChanged", arguments: false)
  }

  /// Formats décodés par la puce (même réponse que sur iPhone). Les puces
  /// Apple qui décodent ces formats vont jusqu'en 4K et lisent la HEVC et
  /// l'AV1 en 10 bits.
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
