import 'notification_actions.dart';
import 'reminder_schedule.dart';

/// Telefonda yerel bildirim kuran taraf (Android / iOS bildirim merkezi).
/// Arayüz ayrı tutulur: denetleyici ve testler gerçek eklentiye bağlı kalmaz.
abstract class ReminderNotifier {
  /// Bu platformda yerel bildirim kurulabilir mi (web / masaüstünde false).
  bool get supported;

  /// Bildirim izni verilmiş mi (sormadan).
  Future<bool> hasPermission();

  /// İzin ister. Daha önce reddedilmişse sistem tekrar sormaz; false döner.
  Future<bool> requestPermission();

  /// Bekleyen tüm bildirimleri silip [items]ı kurar.
  Future<void> replaceAll(List<PlannedNotification> items);

  Future<void> cancelAll();

  /// Uygulamayı bir bildirime dokunarak açtıysa o bildirimin ekranı.
  Future<String?> launchRoute();

  /// Uygulama açıkken ya da arka plandayken bildirime dokunulunca ekran yolu.
  Stream<String> get taps;

  /// Bildirimin altındaki hızlı eylem düğmesine ("+250 ml", "Yaptım") dokunuldu. Uygulama
  /// kapalıyken dokunulan düğme bu akıma gelmez; kayıt doğrudan kuyruğa alınır
  /// ([queueNotificationAction]).
  Stream<NotificationActionTap> get actions;
}

/// Sunucudan gönderilen (FCM) bildirimleri alan taraf. Firebase yapılandırılmadıysa
/// [available] false'tur ve hiçbir şey yapılmaz.
abstract class PushClient {
  bool get available;

  Future<bool> requestPermission();

  /// Bu cihazın bildirim anahtarı; alınamazsa null.
  Future<String?> token();

  Stream<String> get tokenRefreshes;

  /// Sunucu bildirimine dokunulunca açılacak ekran (uygulama arka plandayken).
  Stream<String> get opened;

  /// Uygulama bir sunucu bildirimine dokunularak açıldıysa o ekran, yoksa null.
  Future<String?> initialOpened();
}

/// Firebase kurulmamış / kapalıyken kullanılan boş uygulama.
class NoPushClient implements PushClient {
  const NoPushClient();

  @override
  bool get available => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<String> get opened => const Stream.empty();

  @override
  Future<String?> initialOpened() async => null;
}

/// Bu platformda yerel bildirim kurulamıyor (web, masaüstü) ya da eklenti başlatılamadı.
class UnsupportedNotifier implements ReminderNotifier {
  const UnsupportedNotifier();

  @override
  bool get supported => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> replaceAll(List<PlannedNotification> items) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<String?> launchRoute() async => null;

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Stream<NotificationActionTap> get actions => const Stream.empty();
}
