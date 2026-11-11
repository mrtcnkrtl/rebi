import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/device_location.dart';
import '../../core/i18n.dart';
import '../../core/weather_location.dart';
import '../../state/weather_place_controller.dart';
import '../tw.dart';
import '../widgets/app_sheet.dart';
import '../widgets/common.dart';

/// "Hava için yer" alt sayfası: telefonun konumunu kullan ya da bir şehir ara ve seç. Hava durumu hiçbir koşulda
/// "yok" kalmasın diye konum izni verilmeyen / alınamayan kullanıcıya da bir yol sunar (şehir seçimi izin gerektirmez).
/// Seçim sunucuya kaydedilir; [onChanged] Bugün planını yeni yerle yeniden okur.
Future<void> showWeatherPlaceSheet(
  BuildContext context, {
  required String userId,
  required bool consentAllowed,
  required Future<void> Function() onChanged,
}) {
  final i18n = I18n.instance;
  return AppSheet.show<void>(
    context,
    title: i18n.t('mobileWeatherPlace.title', const {}, 'Hava için yer'),
    body: (ctx) => WeatherPlaceBody(
      userId: userId,
      consentAllowed: consentAllowed,
      onChanged: onChanged,
      onDone: () => Navigator.of(ctx).pop(),
    ),
  );
}

class WeatherPlaceBody extends StatefulWidget {
  const WeatherPlaceBody({
    super.key,
    required this.userId,
    required this.consentAllowed,
    required this.onChanged,
    required this.onDone,
    this.debounce = const Duration(milliseconds: 450),
  });

  final String userId;
  final bool consentAllowed;
  final Future<void> Function() onChanged;
  final VoidCallback onDone;
  final Duration debounce;

  @override
  State<WeatherPlaceBody> createState() => _WeatherPlaceBodyState();
}

class _WeatherPlaceBodyState extends State<WeatherPlaceBody> {
  late final WeatherPlaceController _c = WeatherPlaceController(
    userId: widget.userId,
    consentAllowed: widget.consentAllowed,
    onChanged: widget.onChanged,
    debounce: widget.debounce,
  );
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c.init();
  }

  @override
  void dispose() {
    _c.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _choose(Place p) async {
    if (await _c.choose(p) && mounted) widget.onDone();
  }

  Future<void> _useDevice() async {
    if (await _c.useDevice() && mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    if (!widget.consentAllowed) return _consentOff(context, i18n);
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_c.pref.manual) _current(i18n, _c.pref.name!),
          _device(i18n),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(child: Divider(color: Tw.gray100, height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(i18n.t('mobileWeatherPlace.or', const {}, 'ya da'), style: tx(12.5, c: Tw.gray500)),
                ),
                Expanded(child: Divider(color: Tw.gray100, height: 1)),
              ],
            ),
          ),
          Semantics(
            header: true,
            child: Text(i18n.t('mobileWeatherPlace.cityTitle', const {}, 'Şehrini seç'), style: tx(14.5, w: 7, c: Tw.gray900)),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('weather-place-search'),
            controller: _text,
            onChanged: _c.setQuery,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.words,
            autocorrect: false,
            style: tx(15, c: Tw.gray900),
            decoration: inputDecoration(
              hint: i18n.t('mobileWeatherPlace.searchHint', const {}, 'Şehir ara (örn. Ankara)'),
              prefixIcon: LucideIcons.search,
            ),
          ),
          const SizedBox(height: 8),
          _results(i18n),
          const SizedBox(height: 12),
          Text(i18n.t('mobileToday.advice.attribution', const {}, 'Hava verisi: Open-Meteo.com'), style: tx(11, c: Tw.gray500)),
        ],
      ),
    );
  }

  /// Seçilmiş bir şehir varken: hangi şehrin gösterildiği.
  Widget _current(I18n i18n, String name) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(LucideIcons.mapPin, size: 16, color: Tw.teal700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                i18n.t('mobileWeatherPlace.current', {'place': name}, 'Şu an: {{place}}'),
                style: tx(13.5, w: 6, c: Tw.gray800),
              ),
            ),
          ],
        ),
      );

  Widget _device(I18n i18n) {
    final blockedOrOff = _c.access == LocationAccess.blocked || _c.access == LocationAccess.off;
    final failure = _c.deviceFailure;
    final body = switch (_c.access) {
      LocationAccess.blocked => i18n.t('mobileWeatherPlace.device.bodyBlocked', const {}, 'Konum izni kapalı. Telefon ayarlarından açabilirsin.'),
      LocationAccess.off => i18n.t('mobileWeatherPlace.device.bodyOff', const {}, 'Telefonunun konum servisi kapalı.'),
      _ => i18n.t('mobileWeatherPlace.device.body', const {}, 'Telefonunun konumuna göre. Konum yaklaşık 1 km\'ye yuvarlanır.'),
    };
    return RCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.locateFixed, size: 18, color: Tw.teal700),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i18n.t('mobileWeatherPlace.device.title', const {}, 'Telefonun konumu'), style: tx(14.5, w: 7, c: Tw.gray900, h: snug)),
                    const SizedBox(height: 3),
                    Text(body, style: tx(12.5, c: Tw.gray600, h: relaxed)),
                  ],
                ),
              ),
            ],
          ),
          if (failure != null) ...[
            const SizedBox(height: 10),
            StatusLine(ok: false, text: i18n.t('mobileWeatherPlace.device.fail.${failure.name}')),
            if (failure == LocationFailure.blocked || failure == LocationFailure.serviceOff)
              Align(
                alignment: Alignment.centerLeft,
                child: TextLink(
                  i18n.t('mobileWeatherPlace.device.openSettings', const {}, 'Ayarları aç'),
                  onTap: _c.openSettings,
                  style: tx(13, w: 6, c: Tw.teal700),
                  underline: true,
                ),
              ),
          ],
          const SizedBox(height: 12),
          SecondaryButton(
            key: const Key('weather-place-device'),
            onPressed: _c.busy ? null : (blockedOrOff && failure == null ? _c.openSettingsFromAccess : _useDevice),
            loading: _c.busy,
            minHeight: 48,
            fontSize: 14,
            label: blockedOrOff && failure == null
                ? i18n.t('mobileWeatherPlace.device.openSettings', const {}, 'Ayarları aç')
                : i18n.t('mobileWeatherPlace.device.cta', const {}, 'Konumumu kullan'),
          ),
        ],
      ),
    );
  }

  Widget _results(I18n i18n) {
    switch (_c.phase) {
      case PlaceSearchPhase.idle:
        return _c.error == null ? const SizedBox.shrink() : StatusLine(ok: false, text: _c.error!);
      case PlaceSearchPhase.searching:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.teal600)),
          ),
        );
      case PlaceSearchPhase.empty:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(i18n.t('mobileWeatherPlace.noResults', const {}, 'Bu adla bir yer bulamadık. Yazımı kontrol et.'), style: tx(13.5, c: Tw.gray600, h: relaxed)),
        );
      case PlaceSearchPhase.failed:
        return StatusLine(ok: false, text: _c.error ?? i18n.t('mobileWeatherPlace.searchFailed', const {}, 'Şehir araması şu an yapılamıyor. Biraz sonra tekrar dene.'));
      case PlaceSearchPhase.results:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in _c.results)
              Semantics(
                button: true,
                label: p.label,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _c.busy ? null : () => _choose(p),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Row(
                        children: [
                          Icon(LucideIcons.mapPin, size: 17, color: Tw.gray500),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: tx(15, w: 6, c: Tw.gray900)),
                                if (p.detail.isNotEmpty) Text(p.detail, style: tx(12.5, c: Tw.gray500)),
                              ],
                            ),
                          ),
                          Icon(LucideIcons.chevronRight, size: 18, color: Tw.gray400),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_c.error != null) StatusLine(ok: false, text: _c.error!),
          ],
        );
    }
  }

  /// Konum izni gizlilik onayında kapalıysa: yer seçilemez (yazılan ad ve konum üçüncü tarafa gider); nereden açılacağı söylenir.
  Widget _consentOff(BuildContext context, I18n i18n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(i18n.t('mobileWeatherPlace.consent.title', const {}, 'Konum izni kapalı'), style: tx(15, w: 7, c: Tw.gray900)),
        const SizedBox(height: 6),
        Text(
          i18n.t('mobileWeatherPlace.consent.body', const {}, 'Hava durumunu göstermek için konum bilgisinin işlenmesine izin vermen gerekiyor. Hesap > Gizlilik izinleri bölümünden açabilirsin.'),
          style: tx(13.5, c: Tw.gray600, h: relaxed),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          onPressed: () {
            widget.onDone();
            GoRouter.of(context).go('/dashboard/account');
          },
          label: i18n.t('mobileWeatherPlace.consent.cta', const {}, 'Gizlilik izinlerine git'),
        ),
      ],
    );
  }
}
