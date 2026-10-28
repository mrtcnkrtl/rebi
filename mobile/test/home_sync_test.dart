import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/consent_recovery.dart';
import 'package:rebi/core/demo_user.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/home_sync_controller.dart';

import 'helpers/app_harness.dart';

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeBackend backend;
  late AuthController auth;
  late HomeSyncController sync;

  setUp(() {
    backend = FakeBackend();
    apiHttpClient = backend.client;
    auth = AuthController();
    resetConsentRecovery();
  });

  tearDown(() {
    sync.dispose();
    auth.dispose();
  });

  test('oturum açılınca açılış paketi bir kez alınır', () async {
    sync = HomeSyncController(auth);
    expect(backend.calls('/me/snapshot'), isEmpty, reason: 'oturum yokken istek atılmaz');

    auth.debugSetUser(fakeUser());
    await flush();

    expect(backend.calls('/me/snapshot'), hasLength(1));
    expect(backend.calls('/me/snapshot').single.url.queryParameters['user_id'], testUserId);
    expect(sync.snapshot, isNotNull);
    expect(sync.snapshot!.consent.complete, isTrue);
    expect(consentRecoveryRequests.value, 0);
  });

  test('sürmekte olan istek paylaşılır, bitince yeni istek atılır', () async {
    auth.debugSetUser(fakeUser());
    sync = HomeSyncController(auth);
    final a = sync.refresh();
    final b = sync.refresh();
    expect(await a, same(await b));
    expect(backend.calls('/me/snapshot'), hasLength(1));

    await sync.refresh();
    expect(backend.calls('/me/snapshot'), hasLength(2), reason: 'panel her açıldığında taze veri gerekir');
  });

  test('rıza eksikse onay kutusu istenir', () async {
    backend.snapshot = {
      ...backend.snapshot,
      'consent': {'legal_accepted': false, 'ai_processing_allowed': false},
    };
    auth.debugSetUser(fakeUser());
    sync = HomeSyncController(auth);
    await flush();
    expect(consentRecoveryRequests.value, 1);
  });

  test('yalnızca yapay zekâ izni eksikse de onay istenir', () async {
    backend.snapshot = {
      ...backend.snapshot,
      'consent': {'legal_accepted': true, 'ai_processing_allowed': false},
    };
    auth.debugSetUser(fakeUser());
    sync = HomeSyncController(auth);
    await flush();
    expect(consentRecoveryRequests.value, 1);
  });

  test('kullanıcı verisi sunucuda tutulmuyorsa (synced=false) onay istenmez', () async {
    backend.snapshot = {
      ...backend.snapshot,
      'synced': false,
      'consent': {'legal_accepted': false, 'ai_processing_allowed': false},
    };
    auth.debugSetUser(fakeUser());
    sync = HomeSyncController(auth);
    await flush();
    expect(consentRecoveryRequests.value, 0);
  });

  test('giriş akışı sürerken beklenir, bitince yüklenir', () async {
    sync = HomeSyncController(auth);
    auth.setAuthFlowInProgress(true);
    auth.debugSetUser(fakeUser());
    await flush();
    expect(backend.calls('/me/snapshot'), isEmpty, reason: 'rıza kaydı bitmeden okunursa kutu boşuna açılırdı');

    auth.setAuthFlowInProgress(false);
    await flush();
    expect(backend.calls('/me/snapshot'), hasLength(1));
  });

  test('demo kullanıcı için istek atılmaz', () async {
    auth.debugSetUser(fakeUser(id: demoUserId));
    sync = HomeSyncController(auth);
    await flush();
    expect(backend.calls('/me/snapshot'), isEmpty);
    expect(await sync.refresh(), isNull);
  });

  test('sunucu hatasında paket null kalır ve onay istenmez', () async {
    backend.snapshotFails = true;
    auth.debugSetUser(fakeUser());
    sync = HomeSyncController(auth);
    expect(await sync.refresh(), isNull);
    expect(sync.snapshot, isNull);
    expect(consentRecoveryRequests.value, 0);
  });

  test('çıkışta paket temizlenir', () async {
    auth.debugSetUser(fakeUser());
    sync = HomeSyncController(auth);
    await sync.refresh();
    expect(sync.snapshot, isNotNull);

    auth.debugSetUser(null);
    expect(sync.snapshot, isNull);
  });

  test('rıza kaydedilince izinler yeniden okunur', () async {
    backend.snapshot = {
      ...backend.snapshot,
      'consent': {'legal_accepted': false, 'ai_processing_allowed': false},
    };
    auth.debugSetUser(fakeUser());
    sync = HomeSyncController(auth);
    await sync.refresh();
    expect(consentRecoveryRequests.value, 1);

    backend.snapshot = {
      ...backend.snapshot,
      'consent': {'legal_accepted': true, 'ai_processing_allowed': true, 'location_processing_allowed': true},
    };
    notifyConsentChanged();
    await flush();

    expect(backend.calls('/me/snapshot'), hasLength(2));
    expect(sync.snapshot!.consent.complete, isTrue);
    expect(sync.snapshot!.consent.locationAllowed, isTrue);
    expect(consentRecoveryRequests.value, 1, reason: 'onay verildikten sonra kutu yeniden açılmaz');
  });
}
