import 'dart:async';

import 'package:uuid/uuid.dart';

import 'demo_user.dart';
import 'event_outbox.dart';

const _uuid = Uuid();

class IngestResult {
  const IngestResult({required this.ok, this.skipped = false, this.queued = false, this.data = const {}});

  /// Olay sunucuya yazıldı ya da güvenle kuyruğa alındı. false: sunucu kalıcı olarak reddetti.
  final bool ok;
  final bool skipped;

  /// Sunucuya ulaşılamadı; olay cihazda bekliyor ve bağlantı gelince gönderilecek.
  final bool queued;
  final Map<String, dynamic> data;
}

/// Yerel saat dilimiyle ISO zaman damgası: `2026-10-04T09:12:00+03:00`.
String localIsoTimestamp([DateTime? at]) {
  final now = at ?? DateTime.now();
  final off = now.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final h = off.inHours.abs().toString().padLeft(2, '0');
  final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}'
      'T${two(now.hour)}:${two(now.minute)}:${two(now.second)}$sign$h:$m';
}

/// Olayı sunucuya göndermeden yalnızca kuyruğa alır. Oturumun olmadığı yerde (bildirim düğmesinin
/// arka plan izolatı) kullanılır; kuyruk uygulama açılınca gönderilir. Zaman damgası ve kimlik
/// şimdi üretilir, bu yüzden olay gerçek anıyla kaydedilir.
Future<bool> queueDailyTrackingEvent(String userId, String type, Map<String, dynamic> payload) async {
  if (userId.isEmpty || userId == demoUserId) return false;
  await EventOutbox.instance.add(OutboxEvent(
    id: _uuid.v4(),
    userId: userId,
    type: type,
    payload: payload,
    timestamp: localIsoTimestamp(),
    queuedAt: DateTime.now().millisecondsSinceEpoch,
  ));
  return true;
}

/// Gün içi olay: Supabase daily_events (backend ingest). Demo kullanıcıda atlanır.
/// Mobil sözleşmesine göre (`docs/MOBIL-API.md`) yerel zaman damgası ve tekil
/// `client_event_id` gönderilir. Sunucuya ulaşılamazsa olay cihazda kuyruğa alınır
/// ([EventOutbox]) ve aynı kimlikle yeniden denenir; ağ tekrar denemesi olayı iki kez saydırmaz.
Future<IngestResult> ingestDailyTrackingEvent(
  String? userId,
  String type, [
  Map<String, dynamic> payload = const {},
]) async {
  if (userId == null || userId.isEmpty || userId == demoUserId) {
    return const IngestResult(ok: true, skipped: true);
  }
  final outbox = EventOutbox.instance;
  final event = OutboxEvent(
    id: _uuid.v4(),
    userId: userId,
    type: type,
    payload: payload,
    timestamp: localIsoTimestamp(),
    queuedAt: DateTime.now().millisecondsSinceEpoch,
  );
  final delivery = await outbox.send(event);
  switch (delivery.kind) {
    case DeliveryKind.delivered:
      // Bağlantı çalışıyor: önceden birikmiş olaylar varsa onları da gönder.
      if (outbox.pendingCount(userId) > 0) unawaited(outbox.flush(userId));
      return IngestResult(ok: true, data: delivery.data);
    case DeliveryKind.retry:
      await outbox.add(event);
      return const IngestResult(ok: true, queued: true);
    case DeliveryKind.drop:
      return const IngestResult(ok: false);
  }
}
