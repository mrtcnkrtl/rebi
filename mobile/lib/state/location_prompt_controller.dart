import 'package:flutter/foundation.dart';

import '../core/demo_user.dart';
import '../core/device_location.dart';
import '../core/location_prefs.dart';

/// "Bugün" ekranındaki konum önerisi. Konum, havaya göre kararların (güneş kremi, nemlendirici, dudak balsamı)
/// gerçek hava ile verilmesi içindir; yalnızca şu koşullarda önerilir:
/// kullanıcı konum işlemeye izin vermiş (gizlilik onayı), telefon izni henüz sorulmamış (ya da bir kez reddedilmiş), öneri
/// daha önce kapatılmamış. İzin penceresi **kullanıcı "Konumu aç" deyince** açılır, uygulama açılırken değil.
///
/// Bildirim önerisiyle aynı anda gösterilmez: önce konum (ekrandaki hava gerçek olur), sonra bildirim.
class LocationPromptController extends ChangeNotifier {
  LocationPromptController({required this.userId, required this.consentAllowed, this.onGranted});

  final String userId;

  /// Gizlilik onayında konum işlemeye izin verilmiş mi (sunucudaki `location_processing_allowed`).
  final bool consentAllowed;

  /// İzin verilince çağrılır: Bugün planı konumla yeniden okunur.
  final Future<void> Function()? onGranted;

  bool visible = false;
  bool busy = false;
  bool _disposed = false;

  /// Öneri gösterilsin mi karar ver (izin durumu sorulmadan okunur).
  Future<void> refresh() async {
    var next = false;
    if (consentAllowed && userId != demoUserId && !locationPromptDismissed(userId)) {
      next = await locationAccess() == LocationAccess.askable;
    }
    if (_disposed || next == visible) return;
    visible = next;
    notifyListeners();
  }

  /// "Konumu aç": sistem izin penceresi. Sonuç ne olursa olsun öneri bir daha çıkmaz; izin verildiyse plan konumla yenilenir.
  Future<LocationAccess> allow() async {
    if (busy) return LocationAccess.askable;
    busy = true;
    notifyListeners();
    final result = await requestLocationAccess();
    await dismissLocationPrompt(userId);
    busy = false;
    visible = false;
    if (!_disposed) notifyListeners();
    if (result == LocationAccess.granted) await onGranted?.call();
    return result;
  }

  Future<void> dismiss() async {
    await dismissLocationPrompt(userId);
    visible = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
