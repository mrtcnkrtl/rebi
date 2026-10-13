import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/demo_user.dart';
import 'package:rebi/core/event_outbox.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/outbox_sync_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';

OutboxEvent event(String id, {String userId = testUserId}) => OutboxEvent(
      id: id,
      userId: userId,
      type: 'water_intake',
      payload: const {'ml': 250},
      timestamp: '2026-10-10T09:00:00+03:00',
      queuedAt: DateTime.now().millisecondsSinceEpoch,
    );

Future<void> until(bool Function() condition, {int ms = 1500}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!condition() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late EventOutbox outbox;
  late AuthController auth;
  OutboxSyncController? sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
    backend = FakeBackend();
    apiHttpClient = backend.client;
    outbox = EventOutbox()..debugReset();
    auth = AuthController();
  });

  tearDown(() {
    sync?.dispose();
    sync = null;
    auth.dispose();
  });

  OutboxSyncController make({List<Duration> delays = const [Duration(milliseconds: 30)]}) =>
      sync = OutboxSyncController(auth, outbox: outbox, retryDelays: delays);

  test('oturum açılınca bekleyen olaylar gönderilir', () async {
    await outbox.add(event('a'));
    await outbox.add(event('b'));
    make();
    expect(backend.requests, isEmpty, reason: 'oturum yokken gönderilmez');

    auth.debugSetUser(fakeUser());
    await until(() => outbox.pendingCount(testUserId) == 0);

    expect(outbox.pendingCount(testUserId), 0);
    expect(backend.waterMl, 500);
  });

  test('başka kullanıcının olayları bu oturumla gönderilmez', () async {
    await outbox.add(event('x', userId: 'baska-kullanici'));
    make();
    auth.debugSetUser(fakeUser());
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(backend.requests, isEmpty);
    expect(outbox.pendingCount('baska-kullanici'), 1);
  });

  test('demo kullanıcıda gönderim denenmez', () async {
    await outbox.add(event('d', userId: demoUserId));
    make();
    auth.debugSetUser(fakeUser(id: demoUserId));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(backend.requests, isEmpty);
    expect(sync!.pendingCount, 0);
  });

  test('başarısız gönderim zamanlayıcıyla yeniden denenir ve bağlantı gelince boşalır', () async {
    backend.ingestOffline = true;
    await outbox.add(event('a'));
    auth.debugSetUser(fakeUser());
    make();
    await until(() => backend.calls('/daily_tracking/ingest').length >= 2);
    expect(backend.calls('/daily_tracking/ingest').length, greaterThanOrEqualTo(2), reason: 'zamanlayıcı yeniden denedi');
    expect(sync!.pendingCount, 1);

    backend.ingestOffline = false;
    await until(() => outbox.pendingCount(testUserId) == 0);
    expect(sync!.pendingCount, 0);
    expect(backend.waterMl, 250);
  });

  test('uygulama öne gelince bekleyenler gönderilir', () async {
    backend.ingestOffline = true;
    await outbox.add(event('a'));
    auth.debugSetUser(fakeUser());
    make(delays: const [Duration(hours: 1)]);
    await until(() => backend.calls('/daily_tracking/ingest').isNotEmpty);
    expect(sync!.pendingCount, 1);

    backend.ingestOffline = false;
    sync!.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await until(() => outbox.pendingCount(testUserId) == 0);
    expect(backend.waterMl, 250);
  });

  test('flushNow elle denenir ve gönderilen sayıyı döndürür', () async {
    backend.ingestOffline = true;
    await outbox.add(event('a'));
    auth.debugSetUser(fakeUser());
    make(delays: const [Duration(hours: 1)]);
    await until(() => backend.calls('/daily_tracking/ingest').isNotEmpty);

    backend.ingestOffline = false;
    expect(await sync!.flushNow(), 1);
    expect(sync!.pendingCount, 0);
  });

  test('bekleyen yokken flushNow istek atmaz', () async {
    auth.debugSetUser(fakeUser());
    make();
    expect(await sync!.flushNow(), 0);
    expect(backend.requests, isEmpty);
  });

  test('çıkış yapınca zamanlayıcı durur', () async {
    backend.ingestOffline = true;
    await outbox.add(event('a'));
    auth.debugSetUser(fakeUser());
    make(delays: const [Duration(milliseconds: 40)]);
    await until(() => backend.calls('/daily_tracking/ingest').isNotEmpty);

    auth.debugSetUser(null);
    final count = backend.calls('/daily_tracking/ingest').length;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(backend.calls('/daily_tracking/ingest').length, count, reason: 'oturum yokken deneme sürmez');
    expect(sync!.pendingCount, 0);
  });

  test('yeni olay kuyruğa girince yeniden deneme zamanlanır', () async {
    auth.debugSetUser(fakeUser());
    make();
    backend.ingestOffline = true;
    await outbox.add(event('a'));
    await until(() => backend.calls('/daily_tracking/ingest').isNotEmpty);
    expect(backend.calls('/daily_tracking/ingest'), isNotEmpty);
  });
}
