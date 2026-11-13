import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'local_notifications.dart';
import 'notification_ports.dart';
import 'push_reminder.dart';
import 'reminder_schedule.dart';

/// Uygulama arka plandayken ya da kapalıyken gelen yalnızca-veri hatırlatıcısı (Android). Ayrı bir
/// izolatta çalışır; bildirimi düğmeleriyle kurar, düğmeye dokunuş [rebiNotificationBackground]a gider.
@pragma('vm:entry-point')
Future<void> rebiPushBackground(RemoteMessage message) async {
  // Sistem bildirimi olarak gelen mesajı Android zaten gösterir; ikinci kez gösterilmez.
  if (message.notification != null) return;
  final reminder = PushReminder.fromData(message.data);
  if (reminder == null) return;
  await showPushReminder(reminder, initialize: true);
}

/// Sunucudan gelen (FCM) bildirimler. Yalnızca `FIREBASE_ENABLED=true` derlemelerinde
/// kurulur; Firebase proje dosyaları (`google-services.json`, `GoogleService-Info.plist`)
/// eklenmeden açılırsa native katman başlatılamaz.
class FirebasePushClient implements PushClient {
  FirebasePushClient._();

  /// Firebase'i başlatır. Başarısız olursa [NoPushClient] döner; uygulama yerel bildirimle sürer.
  static Future<PushClient> create() async {
    if (kIsWeb) return const NoPushClient();
    try {
      await Firebase.initializeApp();
      // iOS'ta uygulama açıkken gelen bildirim de gösterilsin (Android'de zaten uygulama içindeyiz).
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, sound: true);
      if (Platform.isAndroid) {
        FirebaseMessaging.onBackgroundMessage(rebiPushBackground);
        // Yalnızca-veri mesajını uygulama açıkken kimse göstermez; düğmeli bildirim burada kurulur.
        FirebaseMessaging.onMessage.listen((message) {
          if (message.notification != null) return;
          final reminder = PushReminder.fromData(message.data);
          if (reminder != null) unawaited(showPushReminder(reminder));
        });
      }
      return FirebasePushClient._();
    } catch (e) {
      debugPrint('Firebase başlatılamadı, push kapalı: $e');
      return const NoPushClient();
    }
  }

  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  static String _routeOf(RemoteMessage m) => routeForReminder(m.data['reminder_id']?.toString());

  @override
  bool get available => true;

  /// Android'de düğmeli bildirimi [rebiPushBackground] kurar. iOS'ta düğmeleri sistem kayıtlı kategoriden
  /// çizer; dokunuşu `AppDelegate.swift` yerel depoya yazar ve [takePendingPushActions] okur.
  @override
  bool get handlesNotificationActions => Platform.isAndroid || Platform.isIOS;

  @override
  Future<bool> requestPermission() async {
    try {
      final settings = await _fcm.requestPermission(alert: true, badge: false, sound: true);
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> token() async {
    try {
      return await _fcm.getToken();
    } catch (_) {
      // iOS'ta APNs anahtarı henüz gelmemiş olabilir; sonraki açılışta ya da yenilemede alınır.
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes => _fcm.onTokenRefresh;

  @override
  Stream<String> get opened => FirebaseMessaging.onMessageOpenedApp.map(_routeOf);

  @override
  Future<String?> initialOpened() async {
    try {
      final message = await _fcm.getInitialMessage();
      return message == null ? null : _routeOf(message);
    } catch (_) {
      return null;
    }
  }
}
