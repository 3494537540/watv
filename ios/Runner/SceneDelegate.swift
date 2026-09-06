import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// QQ OpenSDK 回调走 Scene 的 openURL；转发给 AppDelegate 插件链（tencent_kit）
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    for context in URLContexts {
      let url = context.url
      var options: [UIApplication.OpenURLOptionsKey: Any] = [:]
      if let src = context.options.sourceApplication {
        options[.sourceApplication] = src
      }
      if let annotation = context.options.annotation {
        options[.annotation] = annotation
      }
      options[.openInPlace] = context.options.openInPlace
      if let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate {
        _ = appDelegate.application(
          UIApplication.shared,
          open: url,
          options: options
        )
      }
    }
    super.scene(scene, openURLContexts: URLContexts)
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL,
       let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate {
      _ = appDelegate.application(
        UIApplication.shared,
        continue: userActivity,
        restorationHandler: { _ in }
      )
      // 部分 Flutter 版本用 openURL 兜底 Universal Link
      _ = appDelegate.application(
        UIApplication.shared,
        open: url,
        options: [:]
      )
    }
    super.scene(scene, continue: userActivity)
  }
}
