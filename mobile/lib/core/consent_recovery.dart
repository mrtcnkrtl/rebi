import 'package:flutter/foundation.dart';

/// Rıza kaydı olmayan oturumlarda yapay zekâ uçları 403 döner. O durumda
/// kullanıcıyı çıkışa zorlamak yerine onay kutusunu açarız (web: `lib/consentRecovery.js`).
bool isConsentError(int status, Map<String, dynamic>? data) {
  if (status != 403) return false;
  return (data?['detail'] ?? '').toString().contains('izni gerekli');
}

/// Webdeki `rebi:consent-required` olayı. Her istekte sayaç artar; modal dinler.
final ValueNotifier<int> consentRecoveryRequests = ValueNotifier<int>(0);

void requestConsentRecovery() => consentRecoveryRequests.value++;
