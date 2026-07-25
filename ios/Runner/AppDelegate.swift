import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let configChannel = FlutterMethodChannel(
      name: "com.example.tunga/config",
      binaryMessenger: controller.binaryMessenger
    )

    configChannel.setMethodCallHandler { call, result in
      guard let info = Bundle.main.infoDictionary else {
        result.success("")
        return
      }
      switch call.method {
      case "getMapsApiKey":
        result.success(info["GMS_API_KEY"] as? String ?? "")
      case "getWeatherApiKey":
        result.success(info["WEATHER_API_KEY"] as? String ?? "")
      case "getCustomSearchApiKey":
        result.success(info["CUSTOM_SEARCH_API_KEY"] as? String ?? "")
      case "getCustomSearchEngineId":
        result.success(info["CUSTOM_SEARCH_ENGINE_ID"] as? String ?? "")
      case "getAiApiKey":
        result.success(info["AI_API_KEY"] as? String ?? "")
      default:
        result.notImplemented()
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
