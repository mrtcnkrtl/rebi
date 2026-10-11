import 'package:supabase_flutter/supabase_flutter.dart';

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
