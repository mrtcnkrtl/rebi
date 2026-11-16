import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

const _plusTiers = {
  'plus',
  'pro',
  'premium',
  'plus_1000',
  'plus_lite',
  'plus_basic',
  'plus_starter',
};

/// Mağaza abonelik kademeleri, küçükten büyüğe (RevenueCat entitlement kimlikleriyle aynı).
const storeTiers = ['plus', 'pro', 'max'];

/// Sunucuyla aynı varsayılan günlük soru hakları (`REBI_TIER_DAILY_LIMITS`); yalnızca tanıtım metni içindir,
/// gerçek sınırı sunucu uygular.
const storeTierDailyLimits = {'plus': 50, 'pro': 80, 'max': 120};

/// Yenileme gecikmesinde kullanıcıyı kilitlememek için (sunucuyla aynı).
const _expiryGrace = Duration(minutes: 10);

/// `app_metadata.rebi_store` hâlâ geçerliyse kademe adı; yoksa null. Sunucu `/webhooks/revenuecat` ve
/// `/subscription/sync` ile yazar.
String? activeStoreTier(User? user, {DateTime? now}) {
  final info = user?.appMetadata['rebi_store'];
  if (info is! Map) return null;
  final tier = (info['tier'] ?? '').toString().toLowerCase();
  if (!storeTiers.contains(tier)) return null;
  final exp = info['expires_at_ms'];
  if (exp == null) return tier;
  final ms = exp is num ? exp.toInt() : int.tryParse(exp.toString());
  if (ms == null) return null;
  final expiresAt = DateTime.fromMillisecondsSinceEpoch(ms).add(_expiryGrace);
  return (now ?? DateTime.now()).isBefore(expiresAt) ? tier : null;
}

/// Abonelik hakları sunucunun yönettiği `app_metadata`'dan gelmeli.
bool userHasRebiPlus(User? user) {
  final meta = user?.appMetadata ?? const <String, dynamic>{};
  return meta['rebi_plus'] == true ||
      _plusTiers.contains((meta['subscription_tier'] ?? '').toString().toLowerCase()) ||
      activeStoreTier(user) != null;
}

/// Reklamsız kullanım: herhangi bir ücretli hak (mağaza ya da elle verilmiş Plus).
bool userIsAdFree(User? user) => userHasRebiPlus(user);

/// Bu platformda uygulama içi satın alma (RevenueCat) yapılandırılmış mı?
bool get storePurchasesEnabled {
  if (storePurchasesOverride != null) return storePurchasesOverride!;
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => Env.revenueCatAppleKey.isNotEmpty,
    TargetPlatform.android => Env.revenueCatGoogleKey.isNotEmpty,
    _ => false,
  };
}

/// Testlerde mağaza satın almasını açıp kapatmak için.
@visibleForTesting
bool? storePurchasesOverride;

/// Plus'a geçmenin bir yolu var mı (uygulama içi satın alma ya da ödeme bağlantısı)?
/// Yoksa hiçbir ekranda "Plus'a geç" çağrısı gösterilmez; Plus'ı elle verilmiş hesaplar çalışmaya devam eder.
bool get plusPurchasable => plusPurchasableOverride ?? (storePurchasesEnabled || Env.rebiPlusCheckoutUrl.isNotEmpty);

/// Testlerde satın alma yolunu açıp kapatmak için.
@visibleForTesting
bool? plusPurchasableOverride;

/// Plus girişi (menü satırı, abonelik sayfası bağlantısı) görünsün mü: satın alma varsa ya da hesap Plus ise.
bool plusEntryVisible(User? user) => plusPurchasable || userHasRebiPlus(user);
