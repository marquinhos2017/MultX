import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
    var handler: AudioEngineHandler? = nil
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
     GeneratedPluginRegistrant.register(with: self)
    let controller = window?.rootViewController as! FlutterViewController
    let audioChannel = FlutterMethodChannel(name: "com.example.audio_pad/audio", binaryMessenger: controller.binaryMessenger)
    
    handler = AudioEngineHandler() // mantém referência
    audioChannel.setMethodCallHandler { [weak handler] (call, result) in
    handler?.handle(call, result: result)
  }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

