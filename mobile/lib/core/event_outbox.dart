import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'local_store.dart';

/// Sunucuya henüz ulaşmamış bir gün içi olay. Kimlik ve zaman damgası kullanıcı işlemi
/// yaptığı anda üretilir ve yeniden denemelerde değişmez: sunucu aynı `client_event_id`
/// ile gelen ikinci isteği yazmaz, böylece ağ tekrarı su miktarını iki kez saydırmaz
/// (`docs/MOBIL-API.md` → `POST /daily_tracking/ingest`).
class OutboxEvent {
  const OutboxEvent({
    required this.id,
    required this.userId,
    required this.type,
    required this.payload,
    required this.timestamp,
    required this.queuedAt,
    this.attempts = 0,
  });

  factory OutboxEvent.fromJson(Map<String, dynamic> j) => OutboxEvent(
        id: '${j['id'] ?? ''}',
        userId: '${j['user_id'] ?? ''}',
        type: '${j['type'] ?? ''}',
        payload: j['payload'] is Map ? (j['payload'] as Map).cast<String, dynamic>() : const {},
        timestamp: '${j['timestamp'] ?? ''}',
        queuedAt: j['queued_at'] is num ? (j['queued_at'] as num).toInt() : 0,
        attempts: j['attempts'] is num ? (j['attempts'] as num).toInt() : 0,
      );

  final String id;
  final String userId;
  final String type;
  final Map<String, dynamic> payload;

  /// Yerel saat dilimli ISO zamanı (`2026-10-04T09:12:00+03:00`).
  final String timestamp;

  /// Kuyruğa girdiği an (ms); eski kayıtları ayıklamak için.
  final int queuedAt;
  final int attempts;

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'type': type,
        'payload': payload,
        'timestamp': timestamp,
        'queued_at': queuedAt,
        'attempts': attempts,
      };

  /// `POST /daily_tracking/ingest` gövdesi.
  Map<String, dynamic> toRequest() => {
        'user_id': userId,
        'type': type,
        'payload': payload,
        'source': 'mobile',
        'timestamp': timestamp,
        'client_event_id': id,
      };

  OutboxEvent withAttempts(int next) => OutboxEvent(
        id: id,
        userId: userId,
        type: type,
        payload: payload,
        timestamp: timestamp,
        queuedAt: queuedAt,
        attempts: next,
      );

  /// Olayın gerçekleştiği yerel an; çözülemezse null.
  DateTime? get at => DateTime.tryParse(timestamp)?.toLocal();
}

enum DeliveryKind { delivered, retry, drop }

class Delivery {
  const Delivery(this.kind, {this.status, this.data = const {}});

  final DeliveryKind kind;
  final int? status;
  final Map<String, dynamic> data;
}

/// Sunucu yanıtının ne anlama geldiği: ulaştı, sonra yeniden dene ya da hiç deneme.
/// 429 / 5xx / 408 geçici sayılır. 401 de geçicidir (oturum yenilenebilir). Diğer 4xx
/// (doğrulama, izin) tekrar denemekle düzelmez; kuyruğu tıkamasın diye düşürülür.
DeliveryKind classifyIngestStatus(int status) {
  if (status >= 200 && status < 300) return DeliveryKind.delivered;
  if (status == 401 || status == 408 || status == 425 || status == 429 || status >= 500) return DeliveryKind.retry;
  return DeliveryKind.drop;
}

String _storageKey(String userId) => 'rebi_event_outbox_v1_$userId';

/// Çevrimdışı olay kuyruğu: cihazda kalıcıdır, sırayla ve tekrar denemeye dayanıklı gönderilir.
/// Kullanıcı başına ayrı tutulur; başka bir hesabın olayı asla bu hesabın anahtarıyla gitmez.
class EventOutbox extends ChangeNotifier {
  EventOutbox();

  static final EventOutbox instance = EventOutbox();

  /// Kuyruktaki en fazla olay; aşılırsa en eskiler atılır.
  static const maxQueue = 200;

  /// Bu kadar başarısız denemeden sonra olay atılır.
  static const maxAttempts = 30;

  /// Bu süreden eski olaylar anlamını yitirir (günlük özetler tarih bazlıdır).
  static const maxAge = Duration(days: 7);

  final Map<String, List<OutboxEvent>> _cache = {};
  Future<int>? _flushing;

  /// Bir veya daha fazla olay sunucuya ulaştıkça artar; plan bunu görünce tazelenir.
  int deliveries = 0;

  List<OutboxEvent> _read(String userId) {
    final cached = _cache[userId];
    if (cached != null) return cached;
    final raw = LocalStore.instance.getJson(_storageKey(userId));
    final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    final list = <OutboxEvent>[
      if (raw is List)
        for (final e in raw)
          if (e is Map) OutboxEvent.fromJson(e.cast<String, dynamic>()),
    ].where((e) => e.id.isNotEmpty && e.type.isNotEmpty && e.userId == userId && e.queuedAt >= cutoff).toList();
    return _cache[userId] = list;
  }

  Future<void> _write(String userId, List<OutboxEvent> list) async {
    _cache[userId] = list;
    if (list.isEmpty) {
      await LocalStore.instance.remove(_storageKey(userId));
    } else {
      await LocalStore.instance.setJson(_storageKey(userId), [for (final e in list) e.toJson()]);
    }
  }

  List<OutboxEvent> pending(String userId) => List.unmodifiable(_read(userId));

  int pendingCount(String userId) => _read(userId).length;

  Future<void> add(OutboxEvent event) async {
    final list = [..._read(event.userId)];
    if (list.any((e) => e.id == event.id)) return;
    list.add(event);
    if (list.length > maxQueue) list.removeRange(0, list.length - maxQueue);
    await _write(event.userId, list);
    notifyListeners();
  }

  /// Tek bir isteği gönderir; kuyruğa dokunmaz.
  Future<Delivery> send(OutboxEvent event) async {
    try {
      final res = await apiPost('/daily_tracking/ingest', event.toRequest());
      return Delivery(classifyIngestStatus(res.status), status: res.status, data: res.data);
    } catch (_) {
      // Ağ yok, zaman aşımı, TLS hatası…: olay kaybolmasın, sonra yeniden denensin.
      return const Delivery(DeliveryKind.retry);
    }
  }

  /// Kuyruğu eskiden yeniye gönderir. İlk geçici hatada durur (sıra bozulmasın, sunucu
  /// yorulmasın). Dönüş: sunucuya ulaşan olay sayısı. Aynı anda tek gönderim çalışır.
  Future<int> flush(String userId) => _flushing ??= _flush(userId).whenComplete(() => _flushing = null);

  Future<int> _flush(String userId) async {
    var delivered = 0;
    try {
      while (true) {
        final list = _read(userId);
        if (list.isEmpty) break;
        final event = list.first;
        final result = await send(event);
        if (result.kind == DeliveryKind.retry) {
          final attempts = event.attempts + 1;
          // İstek sürerken kuyruğa yeni olay girmiş olabilir; güncel listeden devam et.
          final rest = _read(userId).where((e) => e.id != event.id).toList();
          await _write(userId, attempts >= maxAttempts ? rest : [event.withAttempts(attempts), ...rest]);
          notifyListeners();
          break;
        }
        await _write(userId, _read(userId).where((e) => e.id != event.id).toList());
        if (result.kind == DeliveryKind.delivered) delivered++;
        notifyListeners();
      }
    } finally {
      if (delivered > 0) {
        deliveries++;
        notifyListeners();
      }
    }
    return delivered;
  }

  /// Hesap silme gibi durumlarda kullanıcının bekleyen olaylarını siler.
  Future<void> clear(String userId) async {
    await _write(userId, const []);
    notifyListeners();
  }

  /// Testlerde bellek önbelleğini ve sayaçları sıfırlar (depolama ayrıca sıfırlanır).
  @visibleForTesting
  void debugReset() {
    _cache.clear();
    _flushing = null;
    deliveries = 0;
  }
}
