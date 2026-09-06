import AVFoundation
import AVKit
import Flutter
import UIKit
import UserNotifications
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var routePickerView: AVRoutePickerView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 本地通知：前台也能出横幅（flutter_local_notifications 要求）
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate =
        self as UNUserNotificationCenterDelegate
    }
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
    // 通知动作 isolate 需要能注册插件
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
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

    let link = FlutterMethodChannel(name: "com.watv.app/link", binaryMessenger: messenger)
    link.setMethodCallHandler { call, result in
      switch call.method {
      case "openUrl":
        guard let urlStr = call.arguments as? [String: Any],
              let raw = urlStr["url"] as? String,
              let url = URL(string: raw) else {
          result(FlutterError(code: "bad_args", message: "url required", details: nil))
          return
        }
        UIApplication.shared.open(url, options: [:]) { ok in
          if ok {
            result(true)
          } else {
            result(FlutterError(code: "open_fail", message: "无法打开链接", details: nil))
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 弹出系统 AirPlay 路由选择器（投视频/音频，非控制中心「屏幕镜像」）
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

      let picker = self.routePickerView ?? AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
      if #available(iOS 13.0, *) {
        picker.prioritizesVideoDevices = true
      }
      picker.isHidden = true
      if picker.superview == nil {
        root.addSubview(picker)
      }
      self.routePickerView = picker

      func fire(_ btn: UIButton) {
        btn.sendActions(for: .touchUpInside)
        result(true)
      }

      // 优先找内部 UIButton 触发系统面板
      if let btn = picker.subviews.compactMap({ $0 as? UIButton }).first {
        fire(btn)
        return
      }
      for sub in picker.subviews {
        if let btn = sub as? UIButton {
          fire(btn)
          return
        }
        for nested in sub.subviews {
          if let btn = nested as? UIButton {
            fire(btn)
            return
          }
        }
      }
      // 再兜底：延迟一帧后重试（部分 iOS 子视图懒加载）
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        if let btn = picker.subviews.compactMap({ $0 as? UIButton }).first {
          fire(btn)
          return
        }
        result(FlutterError(code: "NO_BUTTON", message: "无法唤起 AirPlay 面板", details: nil))
      }
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
