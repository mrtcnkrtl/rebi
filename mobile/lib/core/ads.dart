import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/env.dart';
import 'crash_reporter.dart';

/// Ücretsiz kullanıcıya gösterilen AdMob reklamları. Aboneye hiçbir şey yüklenmez, onay da sorulmaz:
/// hazırlık yalnızca ilk reklam alanı ücretsiz bir kullanıcıya çizildiğinde başlar.
///
/// Sıra (Google'ın önerisi): UMP onayı (AB/İngiltere'de form) → iOS'ta ATT izni → SDK başlatma.
/// Kullanıcı kişiselleştirmeyi reddederse SDK kişiselleştirilmemiş reklam ister; onay hiç alınamazsa reklam yok.
class Ads {
  Ads._();

  static String get bannerUnitId {
    if (kIsWeb) return '';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => Env.admobBannerIos,
      TargetPlatform.android => Env.admobBannerAndroid,
      _ => '',
    };
  }

  /// Bu derlemede reklam açık mı (birim kimliği verilmiş mi)?
  static bool get configured => enabledOverride ?? bannerUnitId.isNotEmpty;

  @visibleForTesting
  static bool? enabledOverride;

  static Future<bool>? _ready;

  /// Reklam istenebilir mi? İlk çağrıda onay akışını yürütür; sonrakiler aynı sonucu bekler.
  static Future<bool> ensureReady() => _ready ??= _prepare();

  static Future<bool> _prepare() async {
    if (!configured) return false;
    try {
      await _gatherConsent();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final status = await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          await AppTrackingTransparency.requestTrackingAuthorization();
        }
      }
      if (!await ConsentInformation.instance.canRequestAds()) return false;
      await MobileAds.instance.initialize();
      return true;
    } catch (e, st) {
      CrashReporting.report(e, st, fatal: false, library: 'ads init');
      return false;
    }
  }

  static Future<void> _gatherConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) {
        if (!done.isCompleted) done.complete();
      }),
      (_) {
        // Onay bilgisi alınamadı (ör. çevrimdışı): önceki oturumun onayıyla devam edilir.
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  /// "Gizlilik seçenekleri" (AB'de onayı sonradan değiştirme) gerekli mi?
  static Future<bool> privacyOptionsRequired() async {
    if (!configured || _ready == null) return false;
    try {
      return await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showPrivacyOptions() => ConsentForm.showPrivacyOptionsForm((_) {});
}
