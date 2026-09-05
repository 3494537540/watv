import AVFoundation
import AVKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var routePickerView: AVRoutePickerView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 播放 / AirPlay / 画中画需要 playback 会话
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
      try session.setActive(true)
    } catch {
      NSLog("[watv] AVAudioSession setup failed: \(error)")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(name: "watv/cast", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "showAirPlayPicker":
        self?.showAirPlayPicker(result: result)
      case "isAirPlayAvailable":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 弹出系统 AirPlay / 屏幕镜像路由选择器
  private func showAirPlayPicker(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let root = self.keyWindowRootView() else {
        result(FlutterError(code: "NO_VIEW", message: "无法获取根视图", details: nil))
        return
      }
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try session.setActive(true)
      } catch {
        NSLog("[watv] AirPlay session: \(error)")
      }

      let picker = self.routePickerView ?? AVRoutePickerView(frame: .zero)
      picker.isHidden = true
      if picker.superview == nil {
        root.addSubview(picker)
      }
      self.routePickerView = picker

      // 优先找内部 UIButton 触发系统面板
      if let btn = picker.subviews.compactMap({ $0 as? UIButton }).first {
        btn.sendActions(for: .touchUpInside)
        result(true)
        return
      }
      // 兜底：遍历更深一层
      for sub in picker.subviews {
        if let btn = sub as? UIButton {
          btn.sendActions(for: .touchUpInside)
          result(true)
          return
        }
        for nested in sub.subviews {
          if let btn = nested as? UIButton {
            btn.sendActions(for: .touchUpInside)
            result(true)
            return
          }
        }
      }
      result(FlutterError(code: "NO_BUTTON", message: "无法唤起 AirPlay 面板", details: nil))
    }
  }

  private func keyWindowRootView() -> UIView? {
    if #available(iOS 13.0, *) {
      let scenes = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
      let window = scenes.first?.windows.first { $0.isKeyWindow }
        ?? scenes.first?.windows.first
      return window?.rootViewController?.view
    }
    return UIApplication.shared.keyWindow?.rootViewController?.view
  }
}
