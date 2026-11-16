import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../../core/ads.dart';
import '../../core/i18n.dart';
import '../../core/subscription.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../tw.dart';

/// Ücretsiz kullanıcıya sayfa sonunda tek bir uyarlanabilir banner; abonede (ya da reklam kapalı derlemede)
/// hiç yer kaplamaz. Altında "Reklamları kaldır" bağlantısı abonelik sayfasına gider.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key, this.padding = const EdgeInsets.only(top: 20)});

  final EdgeInsets padding;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _width;

  /// Banner, bulunduğu alanın genişliğine göre istenir (sayfa kenar boşlukları düşülmüş hâliyle).
  void _ensureFor(int width, bool adFree) {
    if (adFree) {
      if (_ad != null) WidgetsBinding.instance.addPostFrameCallback((_) => _disposeAd());
      _width = null;
      return;
    }
    if (_width == width || width <= 0) return;
    _width = width;
    _load(width);
  }

  Future<void> _load(int width) async {
    if (!Ads.configured) return;
    if (!await Ads.ensureReady() || !mounted) return;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted || _width != width) return;
    _disposeAd();
    final ad = BannerAd(
      adUnitId: Ads.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted && identical(_ad, ad)) {
            setState(() {
              _ad = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  void _disposeAd() {
    _ad?.dispose();
    _ad = null;
    if (_loaded && mounted) setState(() => _loaded = false);
    _loaded = false;
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Ads.configured) return const SizedBox.shrink();
    final adFree = userIsAdFree(context.watch<AuthController>().user);
    return LayoutBuilder(builder: (context, c) {
      _ensureFor(c.maxWidth.isFinite ? c.maxWidth.truncate() : MediaQuery.sizeOf(context).width.truncate(), adFree);
      return _content(context, adFree);
    });
  }

  Widget _content(BuildContext context, bool adFree) {
    final ad = _ad;
    if (!_loaded || ad == null || adFree) return const SizedBox.shrink();
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(i18n.t('mobileAds.label'), style: tx(10.5, w: 6, c: Tw.gray400, ls: .8)),
              if (plusPurchasable)
                GestureDetector(
                  onTap: () => context.go('/dashboard/subscribe'),
                  child: Text(i18n.t('mobileAds.removeAds'), style: tx(11, w: 6, c: theme.fg)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: ad.size.width.toDouble(),
            height: ad.size.height.toDouble(),
            child: AdWidget(ad: ad),
          ),
        ],
      ),
    );
  }
}
