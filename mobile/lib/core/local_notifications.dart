import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'i18n.dart';
import 'local_store.dart';
import 'notification_actions.dart';
import 'notification_ports.dart';
import 'reminder_schedule.dart';

const _channelId = 'rebi_reminders';

/// Bildirimdeki eylem düğmeleri olan hatırlatıcılar (iOS'ta kategori olarak baştan tanıtılır).
const _actionReminderIds = [
  'routine_morning',
  'routine_evening',
  'makeup_log',
  'water_intake',
  'spf_refresh',
  'nutrition_log',
];

String _iosCategory(String reminderId) => 'rebi_$reminderId';

/// Uygulama kapalıyken (ya da arka planda) bildirimdeki düğmeye dokunulunca çalışır. Ayrı bir
/// izolatta çalıştığı için oturum yoktur: olay gönderilmez, yalnızca cihazdaki kuyruğa yazılır ve
/// uygulama bir sonraki açılışta gönderir.
@pragma('vm:entry-point')
Future<void> rebiNotificationBackground(NotificationResponse response) async {
  final actionId = response.actionId;
  if (actionId == null || actionId.isEmpty) return;
  final payload = NotificationPayload.decode(response.payload);
  if (payload == null) return;
  try {
    DartPluginRegistrant.ensureInitialized();
    await LocalStore.init();
    await queueNotificationAction(
      NotificationActionTap(reminderId: payload.reminderId, actionId: actionId, userId: payload.userId),
    );
  } catch (e) {
    debugPrint('Bildirim düğmesi kuyruğa alınamadı: $e');
  }
}

/// `flutter_local_notifications` ile telefona kurulan hatırlatıcılar.
///
/// Her bildirim tek seferliktir ve mutlak bir andır (`TZDateTime.from(at, tz.UTC)`); bu yüzden
/// saat dilimi veritabanına ya da yaz saati hesabına gerek yoktur. Plan her değiştiğinde liste
/// baştan kurulur. Tam saatli alarm izni istenmez: bildirim birkaç dakika kayabilir.
///
/// Bildirimlerin altında hızlı eylem düğmeleri vardır. Android'de düğme uygulamayı açmadan çalışır;
/// iOS'ta uygulama açılır (arka plan izolatı için ek yerel kurulum gerekir).
class LocalNotificationsNotifier implements ReminderNotifier {
  LocalNotificationsNotifier._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _taps = StreamController<String>.broadcast();
  final StreamController<NotificationActionTap> _actions = StreamController<NotificationActionTap>.broadcast();

  /// Eklentiyi hazırlar. Desteklenmeyen platformda (web, masaüstü) ya da hata olursa
  /// [UnsupportedNotifier] döner; uygulama bildirimsiz çalışmaya devam eder.
  static Future<ReminderNotifier> create() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return const UnsupportedNotifier();
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final notifier = LocalNotificationsNotifier._(plugin);
      await plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('@drawable/ic_stat_rebi'),
          // İzin kullanıcı "bildirimleri aç" deyince istenir, uygulama açılırken değil.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: _iosCategories(),
          ),
        ),
        onDidReceiveNotificationResponse: notifier._onResponse,
        onDidReceiveBackgroundNotificationResponse: rebiNotificationBackground,
      );
      await notifier._createChannel();
      return notifier;
    } catch (e) {
      debugPrint('Yerel bildirimler başlatılamadı: $e');
      return const UnsupportedNotifier();
    }
  }

  /// iOS eylem düğmeleri kategori olarak baştan tanıtılır; etiketler başlangıçtaki dilde yazılır.
  static List<DarwinNotificationCategory> _iosCategories() {
    final i18n = I18n.instance;
    return [
      for (final id in _actionReminderIds)
        DarwinNotificationCategory(
          _iosCategory(id),
          actions: [
            for (final a in notificationQuickActions(id))
              DarwinNotificationAction.plain(
                notificationActionId(id, a),
                i18n.t('mobileToday.actions.${a.labelKey}'),
                // iOS arka plan izolatı kurulmadığı için düğme uygulamayı açar.
                options: {DarwinNotificationActionOption.foreground},
              ),
          ],
        ),
    ];
  }

  /// Uygulama çalışırken bildirime ya da düğmesine dokunuldu.
  void _onResponse(NotificationResponse response) {
    final payload = NotificationPayload.decode(response.payload);
    if (payload == null) return;
    final actionId = response.actionId;
    if (actionId != null && actionId.isNotEmpty) {
      _actions.add(NotificationActionTap(reminderId: payload.reminderId, actionId: actionId, userId: payload.userId));
    } else {
      _taps.add(payload.route);
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

  NotificationDetails _details(PlannedNotification n) {
    final i18n = I18n.instance;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        i18n.t('mobileNotifications.channelName'),
        channelDescription: i18n.t('mobileNotifications.channelDescription'),
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(n.body),
        actions: [
          for (final a in n.actions)
            AndroidNotificationAction(a.id, a.label, showsUserInterface: false, cancelNotification: true),
        ],
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentSound: true,
        categoryIdentifier: n.actions.isEmpty ? null : _iosCategory(n.reminderId),
      ),
    );
  }

  @override
  Future<void> replaceAll(List<PlannedNotification> items) async {
    await _plugin.cancelAll();
    for (final n in items) {
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: tz.TZDateTime.from(n.at, tz.UTC),
        notificationDetails: _details(n),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: n.title,
        body: n.body,
        payload: n.payload.encode(),
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
        // Düğmeye dokunarak (iOS) açıldıysa ekran açılmaz; yalnızca gövdeye dokunulunca.
        final response = details?.notificationResponse;
        if (response?.actionId != null && response!.actionId!.isNotEmpty) return null;
        return NotificationPayload.decode(response?.payload)?.route;
      }
    } catch (_) {
      /* başlatma bilgisi okunamadı: normal açılış */
    }
    return null;
  }

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Stream<NotificationActionTap> get actions => _actions.stream;
}
