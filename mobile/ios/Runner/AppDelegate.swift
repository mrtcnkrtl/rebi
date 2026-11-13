import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Uygulama açıkken gelen yerel / push bildirimleri de gösterilsin.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    PushActionInbox.record(response)
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}

/// Sunucu bildiriminin (FCM) düğmesine dokunuş `firebase_messaging` üzerinden Dart'a düğme kimliği olmadan
/// gider. Dokunuş burada `shared_preferences`'ın okuduğu anahtara eklenir; uygulama
/// `takePendingPushActions` ile okuyup kaydeder (`mobile/lib/core/push_action_inbox.dart`).
enum PushActionInbox {
  /// `shared_preferences` anahtarları `flutter.` önekiyle `UserDefaults.standard`a yazılır.
  static let key = "flutter.rebi-pending-push-actions"
  static let limit = 20

  static func record(_ response: UNNotificationResponse) {
    let action = response.actionIdentifier
    guard action != UNNotificationDefaultActionIdentifier,
          action != UNNotificationDismissActionIdentifier,
          response.notification.request.trigger is UNPushNotificationTrigger else { return }
    let info = response.notification.request.content.userInfo
    guard let reminderId = info["reminder_id"] as? String, !reminderId.isEmpty else { return }
    let tap: [String: String] = [
      "reminder_id": reminderId,
      "action_id": action,
      "user_id": info["user_id"] as? String ?? "",
      "day": info["log_date"] as? String ?? "",
    ]
    let defaults = UserDefaults.standard
    var pending: [[String: String]] = []
    if let raw = defaults.string(forKey: key), let data = raw.data(using: .utf8),
       let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
      pending = list
    }
    pending.append(tap)
    guard let data = try? JSONSerialization.data(withJSONObject: Array(pending.suffix(limit))),
          let encoded = String(data: data, encoding: .utf8) else { return }
    defaults.set(encoded, forKey: key)
  }
}
