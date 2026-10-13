import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'i18n.dart';
import 'notification_ports.dart';
import 'reminder_schedule.dart';

const _channelId = 'rebi_reminders';

/// `flutter_local_notifications` ile telefona kurulan hatırlatıcılar.
///
/// Her bildirim tek seferliktir ve mutlak bir andır (`TZDateTime.from(at, tz.UTC)`); bu yüzden
/// saat dilimi veritabanına ya da yaz saati hesabına gerek yoktur. Plan her değiştiğinde liste
/// baştan kurulur. Tam saatli alarm izni istenmez: bildirim birkaç dakika kayabilir.
class LocalNotificationsNotifier implements ReminderNotifier {
  LocalNotificationsNotifier._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _taps = StreamController<String>.broadcast();

  /// Eklentiyi hazırlar. Desteklenmeyen platformda (web, masaüstü) ya da hata olursa
  /// [UnsupportedNotifier] döner; uygulama bildirimsiz çalışmaya devam eder.
  static Future<ReminderNotifier> create() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return const UnsupportedNotifier();
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final notifier = LocalNotificationsNotifier._(plugin);
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // İzin kullanıcı "bildirimleri aç" deyince istenir, uygulama açılırken değil.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final route = response.payload;
          if (route != null && route.isNotEmpty) notifier._taps.add(route);
        },
      );
      await notifier._createChannel();
      return notifier;
    } catch (e) {
      debugPrint('Yerel bildirimler başlatılamadı: $e');
      return const UnsupportedNotifier();
    }
  }

  /// Android'de kanal bir kez oluşur; sunucu bildirimi yerel bildirimden önce gelirse de bu kanalı kullanır.
  Future<void> _createChannel() async {
    final i18n = I18n.instance;
    await _android?.createNotificationChannel(AndroidNotificationChannel(
      _channelId,
      i18n.t('mobileNotifications.channelName'),
      description: i18n.t('mobileNotifications.channelDescription'),
      importance: Importance.defaultImportance,
    ));
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  bool get supported => true;

  @override
  Future<bool> hasPermission() async {
    try {
      if (Platform.isAndroid) return await _android?.areNotificationsEnabled() ?? false;
      final options = await _ios?.checkPermissions();
      return options?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (Platform.isAndroid) return await _android?.requestNotificationsPermission() ?? false;
      return await _ios?.requestPermissions(alert: true, sound: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  NotificationDetails _details(String body) {
    final i18n = I18n.instance;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        i18n.t('mobileNotifications.channelName'),
        channelDescription: i18n.t('mobileNotifications.channelDescription'),
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
    );
  }

  @override
  Future<void> replaceAll(List<PlannedNotification> items) async {
    await _plugin.cancelAll();
    for (final n in items) {
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: tz.TZDateTime.from(n.at, tz.UTC),
        notificationDetails: _details(n.body),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: n.title,
        body: n.body,
        payload: n.route,
      );
    }
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<String?> launchRoute() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        final route = details?.notificationResponse?.payload;
        if (route != null && route.isNotEmpty) return route;
      }
    } catch (_) {
      /* başlatma bilgisi okunamadı: normal açılış */
    }
    return null;
  }

  @override
  Stream<String> get taps => _taps.stream;
}
