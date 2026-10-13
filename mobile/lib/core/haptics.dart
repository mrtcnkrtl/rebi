import 'package:flutter/services.dart';

/// Kısa dokunsal geri bildirim. Desteklemeyen cihazda sessizce yok sayılır; hata uygulamayı bozmaz.
class Haptics {
  Haptics._();

  /// Seçim değişti (adım işareti, sekme).
  static void selection() => _run(HapticFeedback.selectionClick);

  /// Kayıt yapıldı (su eklendi, rutin tamamlandı).
  static void success() => _run(HapticFeedback.lightImpact);

  /// Kayıt başarısız oldu.
  static void failure() => _run(HapticFeedback.mediumImpact);

  static void _run(Future<void> Function() action) {
    try {
      action().catchError((Object _) {});
    } catch (_) {
      /* platform kanalı yok (testler, masaüstü) */
    }
  }
}
