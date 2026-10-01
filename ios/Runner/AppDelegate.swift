import Flutter
import UIKit

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
  }
}
