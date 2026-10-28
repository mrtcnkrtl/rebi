import 'package:flutter/foundation.dart';

/// Rıza kaydı olmayan oturumlarda yapay zekâ uçları 403 döner. O durumda
/// kullanıcıyı çıkışa zorlamak yerine onay kutusunu açarız (web: `lib/consentRecovery.js`).
bool isConsentError(int status, Map<String, dynamic>? data) {
  if (status != 403) return false;
  return (data?['detail'] ?? '').toString().contains('izni gerekli');
}

/// Webdeki `rebi:consent-required` olayı. Her istekte sayaç artar; modal dinler.
final ValueNotifier<int> consentRecoveryRequests = ValueNotifier<int>(0);

bool _consentRecoveryPending = false;

/// Onay istendi ama henüz verilmedi. Açılış paketi, kutu çizilmeden önce de rıza eksiğini
/// bulabilir; sonradan kurulan kutu bu bayrağa bakıp kendini açar.
bool get consentRecoveryPending => _consentRecoveryPending;

void requestConsentRecovery() {
  _consentRecoveryPending = true;
  consentRecoveryRequests.value++;
}

/// Rıza ya da gizlilik izni kaydedildiğinde artar; açılış paketi (izinler) bunu dinleyip yenilenir.
final ValueNotifier<int> consentChanges = ValueNotifier<int>(0);

void notifyConsentChanged() {
  _consentRecoveryPending = false;
  consentChanges.value++;
}

/// Testler arasında genel durumu sıfırlar.
@visibleForTesting
void resetConsentRecovery() {
  _consentRecoveryPending = false;
  consentRecoveryRequests.value = 0;
  consentChanges.value = 0;
}
