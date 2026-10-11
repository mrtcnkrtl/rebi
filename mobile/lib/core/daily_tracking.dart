import 'package:uuid/uuid.dart';

import 'api.dart';
import 'demo_user.dart';

const _uuid = Uuid();

class IngestResult {
  const IngestResult({required this.ok, this.skipped = false, this.data = const {}});

  final bool ok;
  final bool skipped;
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

/// Gün içi olay: Supabase daily_events (backend ingest). Demo kullanıcıda atlanır.
/// Mobil sözleşmesine göre (`docs/MOBIL-API.md`) yerel zaman damgası ve tekil
/// `client_event_id` gönderilir; ağ tekrar denemesi olayı iki kez saydırmaz.
Future<IngestResult> ingestDailyTrackingEvent(
  String? userId,
  String type, [
  Map<String, dynamic> payload = const {},
]) async {
  if (userId == null || userId.isEmpty || userId == demoUserId) {
    return const IngestResult(ok: true, skipped: true);
  }
  try {
    final res = await apiPost('/daily_tracking/ingest', {
      'user_id': userId,
      'type': type,
      'payload': payload,
      'source': 'mobile',
      'timestamp': localIsoTimestamp(),
      'client_event_id': _uuid.v4(),
    });
    return IngestResult(ok: res.ok, data: res.data);
  } catch (_) {
    return const IngestResult(ok: false);
  }
}
