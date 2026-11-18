import 'local_store.dart';
import 'notification_actions.dart';

const _storeKey = 'rebi_notification_snoozes';

/// "30 dk sonra" ile ertelenmiş bir hatırlatma. Plan her değiştiğinde bildirimler baştan kurulduğu için (kurulum önce
/// hepsini siler) ertelemeler diske yazılır ve her kurulumda listeye geri eklenir; soru o arada cevaplanırsa düşer.
class NotificationSnooze {
  const NotificationSnooze({
    required this.userId,
    required this.reminderId,
    required this.day,
    required this.at,
    this.title = '',
    this.body = '',
    this.actions = const [],
  });

  final String userId;
  final String reminderId;

  /// Asıl bildirimin günü (`2026-10-10`): cevap o güne yazılır.
  final String day;
  final DateTime at;

  /// Uygulama kapalıyken kurulan ertelemenin metni (açıkken plan güncel metni verir).
  final String title;
  final String body;
  final List<NotificationActionSpec> actions;

  Map<String, Object?> toJson() => {
        'user_id': userId,
        'reminder_id': reminderId,
        'day': day,
        'at': at.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        'actions': [for (final a in actions) {'id': a.id, 'label': a.label}],
      };

  static NotificationSnooze? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = j['at'];
    final uid = '${j['user_id'] ?? ''}';
    final rid = '${j['reminder_id'] ?? ''}';
    if (at is! num || uid.isEmpty || rid.isEmpty) return null;
    return NotificationSnooze(
      userId: uid,
      reminderId: rid,
      day: '${j['day'] ?? ''}',
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      title: '${j['title'] ?? ''}',
      body: '${j['body'] ?? ''}',
      actions: [
        for (final a in (j['actions'] is List ? j['actions'] as List : const []))
          if (a is Map && '${a['id'] ?? ''}'.isNotEmpty) NotificationActionSpec('${a['id']}', '${a['label'] ?? ''}'),
      ],
    );
  }
}

/// Ertelemeler: kullanıcı başına, hatırlatıcı başına en fazla bir tane (yeni erteleme eskisinin yerine geçer).
class SnoozeStore {
  SnoozeStore._();

  static List<NotificationSnooze> _all() {
    final raw = LocalStore.instance.getJson(_storeKey);
    if (raw is! List) return [];
    return [for (final j in raw) ?NotificationSnooze.fromJson(j)];
  }

  static Future<void> _save(List<NotificationSnooze> items) =>
      LocalStore.instance.setJson(_storeKey, [for (final s in items) s.toJson()]);

  /// Ertelemeyi yazar; aynı kullanıcının aynı hatırlatıcısı için önceki erteleme silinir, geçmiş olanlar temizlenir.
  static Future<void> add(NotificationSnooze snooze, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final kept = [
      for (final s in _all())
        if (s.at.isAfter(t) && !(s.userId == snooze.userId && s.reminderId == snooze.reminderId)) s,
    ];
    await _save([...kept, snooze]);
  }

  /// Bu kullanıcının henüz gelmemiş ertelemeleri.
  static List<NotificationSnooze> pending(String userId, DateTime now) => [
        for (final s in _all())
          if (s.userId == userId && s.at.isAfter(now)) s,
      ];

  /// Soru cevaplandı: o hatırlatıcının ertelemesi düşer.
  static Future<void> remove(String userId, String reminderId) async {
    final all = _all();
    final kept = [
      for (final s in all)
        if (!(s.userId == userId && s.reminderId == reminderId)) s,
    ];
    if (kept.length != all.length) await _save(kept);
  }
}
