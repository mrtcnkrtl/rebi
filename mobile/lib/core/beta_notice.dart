import 'package:flutter/foundation.dart';

import '../config/env.dart';
import 'local_store.dart';

/// Beta sürüm bilgilendirmesi: uygulama ilk açıldığında bir kez gösterilen kısa uyarı ("hata çıkabilir") ve giriş
/// ekranlarındaki küçük "BETA" etiketi. İkisi de `Env.betaBuild` ile birlikte açılıp kapanır; beta bitince derlemeye
/// `--dart-define=REBI_BETA=false` verilmesi yeter.
///
/// Uyarı cihaz başına ve sürümlüdür: metin anlamca değişirse [betaNoticeVersion] artırılıp yeniden gösterilir.
const betaNoticeVersion = 'v1';

const betaNoticeKey = 'rebi-beta-notice-$betaNoticeVersion';

bool hasSeenBetaNotice() => LocalStore.instance.getString(betaNoticeKey) == '1';

/// Açılışta uyarı gösterilmeli mi: beta derlemesi ve bu cihazda bu sürümün uyarısı daha önce gösterilmemiş.
bool shouldShowBetaNotice() => Env.betaBuild && !hasSeenBetaNotice();

Future<void> markBetaNoticeSeen() => LocalStore.instance.setString(betaNoticeKey, '1');

/// Bu açılışta uyarı gösterilecek mi? Yalnızca gerçek uygulama (`RebiApp`) işaretler; testlerin kurduğu uygulamalarda
/// false kalır. Kabuktaki kapı ilk kurulduğunda bayrağı tüketir, böylece açılış başına en çok bir kez gösterilir.
bool betaNoticePending = false;

/// Karşılamanın giriş sekansı (marka kurulumu, ~3 sn) oynarken true. Uyarı sekansın üstüne binmesin diye bu bitene kadar bekler.
final ValueNotifier<bool> startupSequencePlaying = ValueNotifier<bool>(false);
