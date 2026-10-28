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

/// Abonelik hakları sunucunun yönettiği `app_metadata`'dan gelmeli.
bool userHasRebiPlus(User? user) {
  final meta = user?.appMetadata ?? const <String, dynamic>{};
  return meta['rebi_plus'] == true || _plusTiers.contains((meta['subscription_tier'] ?? '').toString().toLowerCase());
}

/// Plus'a geçmenin bir yolu var mı (ödeme bağlantısı ya da ileride uygulama içi satın alma)?
/// Yoksa (v1 mağaza sürümü) hiçbir ekranda "Plus'a geç" çağrısı gösterilmez; Plus'ı elle verilmiş
/// hesaplar çalışmaya devam eder.
bool get plusPurchasable => plusPurchasableOverride ?? Env.rebiPlusCheckoutUrl.isNotEmpty;

/// Testlerde satın alma yolunu açıp kapatmak için.
@visibleForTesting
bool? plusPurchasableOverride;

/// Plus girişi (menü satırı, abonelik sayfası bağlantısı) görünsün mü: satın alma varsa ya da hesap Plus ise.
bool plusEntryVisible(User? user) => plusPurchasable || userHasRebiPlus(user);
