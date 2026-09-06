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
      case "showAirPlayPicker", "showAirPlayVideoPicker":
        self?.showAirPlayVideoPicker(result: result)
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

  /// 弹出 AirPlay「视频」路由选择器（优先 Apple TV，避免只出音箱列表）
  private func showAirPlayVideoPicker(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let root = self.keyWindowRootView() else {
        result(FlutterError(code: "NO_VIEW", message: "无法获取根视图", details: nil))
        return
      }
      do {
        let session = AVAudioSession.sharedInstance()
        // 电影播放模式 + 允许 AirPlay，便于列出视频接收端
        try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try session.setActive(true)
      } catch {
        NSLog("[watv] AirPlay session: \(error)")
      }

      let picker = self.routePickerView ?? AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
      if #available(iOS 13.0, *) {
        // 关键：优先视频设备，减少「纯音频/音箱」面板
        picker.prioritizesVideoDevices = true
      }
      picker.tintColor = .clear
      picker.activeTintColor = .clear
      picker.isHidden = true
      picker.alpha = 0.01
      if picker.superview == nil {
        // 放在可见层级，部分 iOS 版本隐藏控件点不出来
        root.addSubview(picker)
        picker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
          picker.widthAnchor.constraint(equalToConstant: 44),
          picker.heightAnchor.constraint(equalToConstant: 44),
          picker.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: -80),
          picker.topAnchor.constraint(equalTo: root.topAnchor, constant: 80),
        ])
      }
      self.routePickerView = picker
      // 强制布局后再点，避免子按钮尚未生成
      picker.setNeedsLayout()
      picker.layoutIfNeeded()

      func fireButton(in view: UIView) -> Bool {
        if let btn = view as? UIButton {
          btn.sendActions(for: .touchUpInside)
          return true
        }
        for sub in view.subviews {
          if fireButton(in: sub) { return true }
        }
        return false
      }

      if fireButton(in: picker) {
        result(true)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        if fireButton(in: picker) {
          result(true)
        } else {
          result(FlutterError(code: "NO_BUTTON", message: "无法唤起 AirPlay 视频面板", details: nil))
        }
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
