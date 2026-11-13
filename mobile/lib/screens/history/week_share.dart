import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/haptics.dart';
import '../../core/history_trends.dart';
import '../../core/i18n.dart';
import '../../core/user_history.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/brand_caps.dart';
import '../../ui/brand/brand_mark.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/app_sheet.dart';
import '../../ui/widgets/common.dart';

/// Paylaşılabilir haftalık özetin bir günü.
typedef ShareDay = ({DateTime date, bool full, bool any});

/// Son 7 gün (bugün dahil, eskiden yeniye); kaydı olmayan gün boş sayılır.
List<ShareDay> shareWeekDays(List<HistoryDay> days, DateTime today) {
  final end = dateOnly(today);
  final byKey = {for (final d in days) d.logDate: d};
  return [
    for (var back = 6; back >= 0; back--)
      () {
        final date = DateTime(end.year, end.month, end.day - back);
        final p = byKey[dayKey(date)]?.tracking.progress;
        return (date: date, full: p != null && p.morningDone && p.eveningDone, any: p != null && (p.morningDone || p.eveningDone));
      }(),
  ];
}

/// Görseli telefonun paylaşım menüsüne verir. Testler gerçek paylaşım yerine bunu takar.
Future<void> Function(Uint8List png, String text) weekImageSharer = (png, text) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile.fromData(png, mimeType: 'image/png', name: 'rebi-haftam.png')], text: text),
  );
};

/// Önizleme ve "Paylaş" düğmesiyle alt sayfa.
Future<void> showWeekShareSheet(BuildContext context, {required RebiTheme theme, required List<HistoryDay> days, required WeekStats stats}) {
  final i18n = I18n.instance;
  return AppSheet.show<void>(
    context,
    title: i18n.t('mobileShare.title'),
    subtitle: i18n.t('mobileShare.hint'),
    body: (ctx) => _ShareBody(theme: theme, days: shareWeekDays(days, DateTime.now()), stats: stats),
  );
}

class _ShareBody extends StatefulWidget {
  const _ShareBody({required this.theme, required this.days, required this.stats});

  final RebiTheme theme;
  final List<ShareDay> days;
  final WeekStats stats;

  @override
  State<_ShareBody> createState() => _ShareBodyState();
}

class _ShareBodyState extends State<_ShareBody> {
  final _boundary = GlobalKey();
  bool _busy = false;
  String _error = '';

  Future<void> _share() async {
    final i18n = I18n.instance;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final render = _boundary.currentContext?.findRenderObject();
      if (render is! RenderRepaintBoundary) throw StateError('render');
      // Kart 360×640 mantıksal boyutta çizilir; 3 kat ölçekle hikâye boyutu (1080×1920) olur.
      final image = await render.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('png');
      final full = widget.days.where((d) => d.full).length;
      await weekImageSharer(data.buffer.asUint8List(), i18n.t('mobileShare.shareText', {'n': full}));
      Haptics.success();
    } catch (_) {
      if (mounted) setState(() => _error = i18n.t('mobileShare.failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              // Önizleme ekrana sığacak kadar küçültülür; paylaşılan görsel tam boyuttur.
              child: SizedBox(
                width: 216,
                height: 384,
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _boundary,
                    child: WeekShareCard(days: widget.days, stats: widget.stats, lang: i18n.lang),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            onPressed: _busy ? null : _share,
            loading: _busy,
            color: widget.theme.primary,
            icon: LucideIcons.share2,
            label: i18n.t('mobileShare.share'),
            minHeight: 54,
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_error, style: tx(13, w: 5, c: Tw.red600)),
          ],
        ],
      ),
    );
  }
}

/// Paylaşılan görsel: 360×640 (9:16), orman yeşili zemin, krem yazı. Yalnızca alışkanlık özeti içerir
/// (fotoğraf, stres, uyku ya da cilt sorunu yok).
class WeekShareCard extends StatelessWidget {
  const WeekShareCard({super.key, required this.days, required this.stats, required this.lang});

  final List<ShareDay> days;
  final WeekStats stats;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    const cream = Brand.cream;
    final soft = cream.withValues(alpha: .72);
    final faint = cream.withValues(alpha: .18);
    final full = days.where((d) => d.full).length;
    final range = '${DateFormat.MMMd(lang).format(days.first.date)} – ${DateFormat.MMMd(lang).format(days.last.date)}';
    final names = i18n.tList('dashboard.weekDays', const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
    final water = stats.avgWaterMl;
    final nf1 = NumberFormat('#,##0.0', lang);

    Widget stat(String value, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Brand.serif(34, color: cream, h: 1)),
              const SizedBox(height: 6),
              Text(label, style: tx(12.5, c: soft, h: 1.3)),
            ],
          ),
        );

    return Container(
      width: 360,
      height: 640,
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
      // Düz orman yeşili (tasarım dili: kartlarda gradyan yok).
      color: Brand.forest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandMark(size: 30),
              const SizedBox(width: 10),
              Text('Rebi', style: Brand.serif(22, color: cream, h: 1)),
            ],
          ),
          const Spacer(flex: 3),
          Text(brandCaps(i18n.t('mobileShare.eyebrow'), lang), style: tx(12, w: 7, c: soft, ls: brandTracking(lang, 2.4))),
          const SizedBox(height: 6),
          Text(range, style: tx(14, w: 5, c: soft)),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$full', style: Brand.serif(120, color: cream, h: 1, weight: 500)),
              Text('/7', style: Brand.serif(42, color: soft, h: 1)),
            ],
          ),
          const SizedBox(height: 8),
          Text(i18n.t('mobileShare.routineCaption'), style: tx(18, w: 5, c: cream, h: 1.35)),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final d in days)
                Column(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d.full ? cream : Colors.transparent,
                        border: d.full ? null : Border.all(color: d.any ? cream : faint, width: 1.6),
                      ),
                      child: d.full
                          ? const Icon(LucideIcons.check, size: 15, color: Brand.forest)
                          : d.any
                          ? Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: cream))
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(names.length == 7 ? names[d.date.weekday - 1] : '', style: tx(11, w: 5, c: soft)),
                  ],
                ),
            ],
          ),
          const Spacer(flex: 2),
          Container(height: 1, color: faint),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (water != null && water > 0) ...[
                stat('${nf1.format(water / 1000)} L', i18n.t('mobileShare.water')),
                const SizedBox(width: 16),
              ],
              stat('${stats.spfRefreshes}', i18n.t('mobileShare.spf')),
            ],
          ),
          const Spacer(),
          Text('rebiovil.com', style: tx(12.5, w: 6, c: soft, ls: .4)),
        ],
      ),
    );
  }
}
