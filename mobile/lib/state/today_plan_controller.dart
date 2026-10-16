import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/daily_tracking.dart';
import '../core/device_location.dart';
import '../core/event_outbox.dart';
import '../core/shelf.dart';
import '../core/today_plan.dart';

/// Bir gün içi kaydın sonucu.
enum LogOutcome {
  /// Sunucuya yazıldı.
  sent,

  /// Sunucuya ulaşılamadı; cihazda bekliyor, bağlantı gelince gönderilecek.
  queued,

  /// Kaydedilemedi (sunucu kalıcı olarak reddetti ya da demo kullanıcı).
  failed;

  bool get saved => this != failed;
}

/// Panelin "bugün" bölümü için `GET /today/plan` durumu ve gün içi kayıtlar.
/// Kayıtların hepsi [ingestDailyTrackingEvent] üzerinden geçer; sunucuya ulaşamayanlar
/// [EventOutbox]ta bekler ve gösterilen ilerlemeye eklenir: ekran = sunucu durumu + bekleyenler.
class TodayPlanController extends ChangeNotifier {
  TodayPlanController({required this.userId, EventOutbox? outbox, DateTime Function()? clock})
      : _outbox = outbox ?? EventOutbox.instance,
        _clock = clock ?? DateTime.now {
    _seenDeliveries = _outbox.deliveries;
    _outbox.addListener(_onOutbox);
  }

  final String userId;
  final EventOutbox _outbox;
  final DateTime Function() _clock;

  /// Planın en son başarıyla okunduğu an; uygulama uzun süre arka plandaysa bayatlığı buradan anlaşılır.
  DateTime? _loadedAt;

  TodayPlan? _base;
  bool loading = false;

  /// Son yükleme başarısız oldu ve elde eski plan yok.
  bool failed = false;

  bool _useLocation = false;
  int _version = 0;
  int _seenDeliveries = 0;
  bool _disposed = false;

  /// Gönderilmeyi bekleyen kayıt sayısı.
  int get pendingCount => _outbox.pendingCount(userId);

  /// Sunucudaki plan + henüz gönderilmemiş bugünkü kayıtların etkisi.
  TodayPlan? get plan {
    final base = _base;
    if (base == null) return null;
    final today = _clock();
    var progress = base.progress;
    var shelf = base.productsOut;
    for (final event in _outbox.pending(userId)) {
      final at = event.at;
      final isToday = at != null && at.year == today.year && at.month == today.month && at.day == today.day;
      if (isToday) progress = progress.withEvent(event.type, event.payload);
      // Rafım gün sınırı tanımaz: bekleyen "bitti" / "aldım" hangi gün işaretlendiyse geçerlidir.
      shelf = shelfWith(shelf, event.type, event.payload, now: at);
    }
    return base.withProgress(progress).withShelf(shelf);
  }

  /// [useLocation]: konum izni varsa canlı hava için cihaz konumu gönderilir.
  Future<void> load({required bool useLocation}) {
    _useLocation = useLocation;
    return _fetch(showSpinner: _base == null);
  }

  Future<void> reload() => _fetch(showSpinner: false);

  /// Uygulama öne geldiğinde: plan [maxAge]den eskiyse ya da gün değiştiyse (gece yarısı geçti: dünün planı,
  /// dünün hatırlatıcıları) yeniden okur. Taze plana dokunmaz.
  Future<void> reloadIfStale({Duration maxAge = const Duration(minutes: 10)}) {
    final at = _loadedAt;
    final now = _clock();
    final stale = at == null || now.difference(at) >= maxAge || at.day != now.day || at.month != now.month;
    return _base == null || !stale ? Future.value() : reload();
  }

  Future<void> _fetch({required bool showSpinner}) async {
    final version = ++_version;
    if (showSpinner) {
      loading = true;
      failed = false;
      _notify();
    }
    TodayPlan? next;
    try {
      final at = _useLocation ? await lookupDeviceLocation() : null;
      next = await fetchTodayPlan(userId, lat: at?.lat, lon: at?.lon);
    } catch (_) {
      /* ağ yok: eldeki plan gösterilmeye devam eder */
    }
    // Daha yeni bir istek başladıysa bu yanıt eskidir.
    if (_disposed || version != _version) return;
    loading = false;
    if (next != null) {
      _base = next;
      _loadedAt = _clock();
      failed = false;
    } else {
      failed = _base == null;
    }
    _notify();
  }

  /// Gün içi olayı kaydeder. Sunucuya yazıldıysa planı tazeler; ulaşılamadıysa kuyruğa alınır
  /// ve ilerleme hemen güncel görünür.
  Future<LogOutcome> log(String type, [Map<String, dynamic> payload = const {}]) async {
    final result = await ingestDailyTrackingEvent(userId, type, payload);
    if (result.skipped || !result.ok) return LogOutcome.failed;
    if (result.queued) {
      _notify();
      return LogOutcome.queued;
    }
    final aggregated = result.data['aggregated'];
    final current = _base;
    if (!_disposed && current != null && aggregated is Map && aggregated.isNotEmpty) {
      // Sunucu toplamı günün ilerlemesini verir; Rafım'ı plan yeniden okunana kadar olayın etkisiyle güncel tut.
      _base = current.withProgress(DayProgress.fromJson(aggregated)).withShelf(shelfWith(current.productsOut, type, payload));
      _notify();
    }
    unawaited(reload());
    return LogOutcome.sent;
  }

  void _onOutbox() {
    // Kuyruk gönderilince sunucu toplamı değişir: planı yeniden oku.
    if (_outbox.deliveries != _seenDeliveries) {
      _seenDeliveries = _outbox.deliveries;
      unawaited(reload());
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _outbox.removeListener(_onOutbox);
    super.dispose();
  }
}
