import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "org.zerosync/security_window_guard"
  private var isSecureEnabled = false
  private var obscureView: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        guard let self = self else { return }
        switch call.method {
        case "enableSecureScreen":
          self.isSecureEnabled = true
          result(true)
        case "disableSecureScreen":
          self.isSecureEnabled = false
          self.removePrivacyShield()
          result(true)
        case "isSecureScreenEnabled":
          result(self.isSecureEnabled)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    if isSecureEnabled {
      applyPrivacyShield()
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    removePrivacyShield()
  }

  private func applyPrivacyShield() {
    guard obscureView == nil, let window = self.window else { return }
    let blurEffect = UIBlurEffect(style: .dark)
    let blurView = UIVisualEffectView(effect: blurEffect)
    blurView.frame = window.bounds
    blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(blurView)
    obscureView = blurView
  }

  private func removePrivacyShield() {
    obscureView?.removeFromSuperview()
    obscureView = nil
  }
}

