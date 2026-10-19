import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/routine_usage.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/glyphs.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import '../today/today_widgets.dart';

/// Rutin ekranı parçalarının ortak bağlamı.
class RoutineCtx {
  const RoutineCtx({required this.i18n, required this.theme, required this.localized, required this.weekDays});

  final I18n i18n;
  final RebiTheme theme;
  final bool localized;
  final List<String> weekDays;
}

/// Bir adım hakkında Rebi'ye sorulacak hazır soru; sohbet bunu açılışta kendiliğinden gönderir.
void askRebiAboutStep(BuildContext context, RoutineItem item, RoutineCtx ctx) {
  final name = pickAction(item, localized: ctx.localized).trim();
  if (name.isEmpty) return;
  context.go('/dashboard/chat', extra: {'prompt': ctx.i18n.t('mobileRoutine.askPrompt', {'item': name})});
}

/// Bölüm başlığı: soluk simge kutusu, başlık ve tek satır açıklama.
class RoutineSectionTitle extends StatelessWidget {
  const RoutineSectionTitle({super.key, required this.icon, required this.title, this.subtitle, required this.color, this.topGap = 28});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final double topGap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: topGap, bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 1), child: Text(title, style: heading(20, h: 1.2))),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: tx(12, c: Tw.gray500, h: snug)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

/// Rutin adımı: numara, ad, rozetler ve "Neden bu ürün?" açılır detayı. İstenirse "Rebi'ye sor" bağlantısı.
class RoutineStepTile extends StatefulWidget {
  const RoutineStepTile({super.key, required this.item, required this.ctx, this.step});

  final RoutineItem item;
  final RoutineCtx ctx;

  /// Uygulama sırası; null ise adım numarasız (yaşam önerisi) ve simgeyle gösterilir.
  final int? step;

  @override
  State<RoutineStepTile> createState() => _RoutineStepTileState();
}

class _RoutineStepTileState extends State<RoutineStepTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = widget.ctx;
    final i18n = c.i18n;
    final theme = c.theme;
    final skincare = isSkincareStep(item);
    final usage = routineStepUsage(item, i18n);
    final detail = pickDetail(item, localized: c.localized);
    final hasMore = detail.isNotEmpty || usage.isNotEmpty;
    final action = str(item['action']);
    final actionLower = action.toLowerCase();
    // "Nemlendirici: seramid + skualan" gibi satırlar bir hedef içerik örneğidir; tek üründe hepsi aranmaz.
    final comboHint = skincare &&
        action.contains('+') &&
        (actionLower.contains('nemlendirici') ||
            actionLower.contains('bariyer') ||
            actionLower.contains('onarım') ||
            actionLower.contains('onarim') ||
            actionLower.contains('krem'));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: theme.primary.withValues(alpha: .12), shape: BoxShape.circle),
            child: widget.step != null
                ? Text('${widget.step}', style: tx(13, w: 8, c: theme.fg))
                : Icon(glyphForEmoji(str(item['icon']), fallback: LucideIcons.leaf), size: 16, color: theme.fg),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(pickAction(item, localized: c.localized), style: tx(15, w: 6, c: Tw.gray900, h: snug)),
                ),
                StructuredBadges(item: item),
                if (comboHint) ...[
                  const SizedBox(height: 6),
                  Text(i18n.t('mobileRoutine.comboHint'), style: tx(12, c: Tw.gray500, h: relaxed)),
                ],
                if (hasMore) ...[
                  const SizedBox(height: 2),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _open = !_open),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                          child: Text(
                            _open
                                ? i18n.t('common.hide')
                                : skincare
                                    ? i18n.t('dashboard.whySkincareButton')
                                    : i18n.t('common.details'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tx(12.5, w: 6, c: theme.fg),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14, color: theme.fg),
                      ]),
                    ),
                  ),
                ],
                if (_open) ...[
                  if (detail.isNotEmpty)
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: (skincare || usage.isNotEmpty) ? i18n.t('dashboard.shortWhy') : i18n.t('dashboard.summary'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' $detail'),
                      ]),
                      style: tx(12.5, c: Tw.gray600, h: relaxed),
                    ),
                  if (usage.isNotEmpty) ...[
                    if (detail.isNotEmpty) const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: skincare ? i18n.t('dashboard.howToApply') : i18n.t('dashboard.howToDo'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' $usage'),
                      ]),
                      style: tx(12.5, c: Tw.gray600, h: relaxed),
                    ),
                  ],
                  const SizedBox(height: 4),
                  TextLink(
                    i18n.t('mobileRoutine.askRebi'),
                    onTap: () => askRebiAboutStep(context, item, c),
                    style: tx(12.5, w: 7, c: theme.fg),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sabah ya da akşam: başlık satırı ve numaralı adımlar (aralarında ince çizgi).
class RoutineBlockCard extends StatelessWidget {
  const RoutineBlockCard({super.key, required this.icon, required this.title, required this.ctx, required this.steps, this.notes = const []});

  final IconData icon;
  final String title;
  final RoutineCtx ctx;
  final List<RoutineItem> steps;

  /// Aynı bloğun yaşam önerileri (numarasız).
  final List<RoutineItem> notes;

  @override
  Widget build(BuildContext context) {
    final theme = ctx.theme;
    final i18n = ctx.i18n;
    return RCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: theme.fg),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: heading(20, h: 1.2))),
            if (steps.isNotEmpty)
              Text(i18n.t('mobileRoutine.stepCount', {'n': steps.length}), style: tx(12, c: Tw.gray500)),
          ]),
          const SizedBox(height: 4),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const Hairline(indent: 44),
            RoutineStepTile(key: ValueKey('${title}_step_$i'), item: steps[i], ctx: ctx, step: i + 1),
          ],
          if (notes.isNotEmpty) ...[
            const Hairline(),
            for (var i = 0; i < notes.length; i++) ...[
              if (i > 0) const Hairline(indent: 44),
              RoutineStepTile(key: ValueKey('${title}_note_$i'), item: notes[i], ctx: ctx),
            ],
          ],
        ],
      ),
    );
  }
}

/// Katlanır kart: başlık satırı her zaman görünür, içerik dokununca açılır.
class CollapsibleCard extends StatefulWidget {
  const CollapsibleCard({super.key, required this.icon, required this.title, this.subtitle, required this.color, required this.child, this.initiallyOpen = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final Widget child;
  final bool initiallyOpen;

  @override
  State<CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<CollapsibleCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return RCard(
      padding: EdgeInsets.zero,
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: widget.title,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: widget.color.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(widget.icon, size: 18, color: widget.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: tx(14.5, w: 7, c: Tw.gray800, h: snug)),
                        if (widget.subtitle != null) Text(widget.subtitle!, style: tx(12, c: Tw.gray500, h: snug)),
                      ],
                    ),
                  ),
                  Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: Tw.gray500),
                ]),
              ),
            ),
          ),
          if (_open) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: widget.child),
        ],
      ),
    );
  }
}

/// Günlük yaşam dengesi notu: risk düzeyine göre solda renkli şerit, kısa metin ve "Ayrıntılar".
class DailyBalanceCard extends StatefulWidget {
  const DailyBalanceCard({super.key, required this.item, required this.flowDebug, required this.ctx});

  final RoutineItem? item;
  final Object? flowDebug;
  final RoutineCtx ctx;

  @override
  State<DailyBalanceCard> createState() => _DailyBalanceCardState();
}

class _DailyBalanceCardState extends State<DailyBalanceCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    if (it == null) return const SizedBox.shrink();
    final ctx = widget.ctx;
    final fd = widget.flowDebug is Map ? (widget.flowDebug as Map).cast<String, dynamic>() : null;
    final action = pickAction(it, localized: ctx.localized);
    final detail = pickDetail(it, localized: ctx.localized);
    final level = dailyBalanceLevel(it, fd);
    final (stripe, pillBg, pillFg) = switch (level) {
      'crisis' => (Tw.red500, Tw.red100, Tw.red800),
      'high' => (Tw.orange500, Tw.orange100, Tw.orange800),
      'moderate' => (Tw.amber500, Tw.amber100, Tw.amber900),
      _ => (ctx.theme.primary, ctx.theme.primary.withValues(alpha: .12), ctx.theme.primaryDark),
    };
    final risk = fd?['risk_info'];
    final lv = risk is Map ? risk['level'] : null;
    String pillText;
    if (ctx.localized && truthy(lv)) {
      pillText = ctx.i18n.t('dashboard.riskLevels.$lv');
    } else if (risk is Map && truthy(risk['label'])) {
      pillText = str(risk['label']);
    } else {
      final t = action.replaceFirst(RegExp(r'^Günlük denge:\s*', caseSensitive: false), '').trim();
      pillText = t.isEmpty ? '—' : t;
    }
    final long = detail.length > 150;

    return RCard(
      leftBorderColor: stripe,
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(LucideIcons.activity, size: 17, color: ctx.theme.fg),
              Text(ctx.i18n.t('dashboard.dailyBalanceTitle'), style: tx(14.5, w: 7, c: Tw.gray800)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(999)),
                child: Text(pillText, style: tx(11, w: 6, c: pillFg)),
              ),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              maxLines: long && !_open ? 3 : null,
              overflow: long && !_open ? TextOverflow.ellipsis : null,
              style: tx(13, c: Tw.gray700, h: relaxed),
            ),
            if (long)
              TextLink(
                ctx.i18n.t(_open ? 'common.hide' : 'common.details'),
                onTap: () => setState(() => _open = !_open),
                style: tx(12.5, w: 6, c: ctx.theme.fg),
              ),
          ],
        ],
      ),
    );
  }
}

/// Akşam etkenlerinin sabah kullanılmaması uyarısı.
class MorningHintsCard extends StatelessWidget {
  const MorningHintsCard({super.key, required this.hints, required this.ctx});

  final List<String> hints;
  final RoutineCtx ctx;

  @override
  Widget build(BuildContext context) {
    return RCard(
      padding: const EdgeInsets.all(16),
      radius: 20,
      borderColor: Tw.amber200,
      color: Color.alphaBlend(Tw.amber50.withValues(alpha: .6), Tw.surface),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(LucideIcons.triangleAlert, size: 18, color: Tw.amber600)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ctx.i18n.t('dashboard.morningUsageTitle'), style: tx(14.5, w: 7, c: Tw.amber950)),
                const SizedBox(height: 6),
                for (final line in hints)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7, right: 8),
                        child: Container(width: 4, height: 4, decoration: BoxDecoration(color: Tw.amber700, shape: BoxShape.circle)),
                      ),
                      Expanded(child: Text(line, style: tx(13, c: Tw.gray800, h: relaxed))),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Günlük check-in'e giden kart (düz, vurgu tonlu).
class CheckinPromptCard extends StatelessWidget {
  const CheckinPromptCard({super.key, required this.ctx, this.done = false, this.big = false});

  final RoutineCtx ctx;
  final bool done;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = ctx.theme;
    final i18n = ctx.i18n;
    return RCard(
      onTap: () => context.go('/dashboard/checkin'),
      radius: 20,
      borderColor: theme.primaryLight,
      color: Color.alphaBlend(theme.primary.withValues(alpha: .06), Tw.surface),
      child: Row(
        children: [
          Container(
            width: big ? 46 : 40,
            height: big ? 46 : 40,
            decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(14)),
            child: Icon(done ? LucideIcons.circleCheck : LucideIcons.clipboardCheck, size: big ? 24 : 20, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('dashboard.dailyCheckinTitle'), style: tx(big ? 16 : 14.5, w: 7, c: Tw.gray800)),
                Text(
                  done
                      ? i18n.t('mobileToday.checkinDoneToday')
                      : big
                          ? i18n.t('dashboard.dailyCheckinSubtitle')
                          : i18n.t('dashboard.feelsTodayHint'),
                  style: tx(12, c: Tw.gray500, h: snug),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.arrowRight, size: 20, color: Tw.gray400),
        ],
      ),
    );
  }
}

/// Son check-in'in yapay zekâ notu.
class AiNoteCard extends StatelessWidget {
  const AiNoteCard({super.key, required this.checkinResult, required this.ctx, this.showChanges = false});

  final Map checkinResult;
  final RoutineCtx ctx;
  final bool showChanges;

  @override
  Widget build(BuildContext context) {
    final changes = checkinResult['changes'];
    return RCard(
      leftBorderColor: ctx.theme.primary,
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.sparkles, size: 18, color: ctx.theme.fg)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ctx.i18n.t('dashboard.lastCheckinNoteTitle'), style: tx(12, w: 7, c: Tw.gray600, ls: .4)),
                const SizedBox(height: 4),
                Text(str(checkinResult['ai_note']), style: tx(14, c: Tw.gray700, h: relaxed)),
                if (showChanges && changes is List && changes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(LucideIcons.info, size: 14, color: Tw.amber600),
                    const SizedBox(width: 6),
                    Flexible(child: Text(ctx.i18n.t('checkin.changesCount', {'count': changes.length}), style: tx(12, c: Tw.amber700))),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hava durumu tek satırda: düz, vurgu renginde değil nötr.
class WeatherLine extends StatelessWidget {
  const WeatherLine({super.key, required this.weather, required this.ctx});

  final Map weather;
  final RoutineCtx ctx;

  @override
  Widget build(BuildContext context) {
    final i18n = ctx.i18n;
    return RCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      radius: 18,
      child: Row(children: [
        Icon(LucideIcons.cloudSun, size: 17, color: Tw.amber600),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${i18n.t('dashboard.weatherTitle')} · ${str(weather['temperature'])}°C · UV ${str(weather['uv_index'])}'
            '${truthy(weather['humidity']) ? ' · ${i18n.t('mobileRoutine.humidity', {'value': str(weather['humidity'])})}' : ''}',
            style: tx(13, w: 6, c: Tw.gray700),
          ),
        ),
      ]),
    );
  }
}

/// Rutindeki aktifler (dolap ∩ kısıtlar ∩ bugünün adımları).
class ActivePlanCard extends StatelessWidget {
  const ActivePlanCard({super.key, required this.activePlan, required this.ctx});

  final List<Map> activePlan;
  final RoutineCtx ctx;

  @override
  Widget build(BuildContext context) {
    final i18n = ctx.i18n;
    return CollapsibleCard(
      icon: LucideIcons.sparkles,
      title: i18n.t('dashboard.activePlanTitle'),
      subtitle: i18n.t('dashboard.activePlanSubtitle'),
      color: ctx.theme.fg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in activePlan) ...[
            Builder(builder: (_) {
              final whenKey = p['when'] == 'morning'
                  ? 'dashboard.activePlanWhenMorning'
                  : p['when'] == 'evening'
                      ? 'dashboard.activePlanWhenEvening'
                      : 'dashboard.activePlanWhenBoth';
              final name = [p['name_tr'], p['name'], p['active']].firstWhere(truthy, orElse: () => '');
              final why = [p['why'], p['why_tr']].firstWhere(truthy, orElse: () => '');
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text(str(name), style: tx(14, w: 6, c: Tw.gray800, h: snug))),
                      const SizedBox(width: 8),
                      Text(i18n.t(whenKey).toUpperCase(), style: tx(10.5, w: 7, c: Tw.gray500, ls: .6)),
                    ]),
                    if (truthy(why)) ...[
                      const SizedBox(height: 2),
                      Text(str(why), style: tx(12.5, c: Tw.gray600, h: relaxed)),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// "Önerilen maddeleri nasıl seçersin?" kısa rehberi.
class HowToChooseCard extends StatelessWidget {
  const HowToChooseCard({super.key, required this.ctx});

  final RoutineCtx ctx;

  @override
  Widget build(BuildContext context) {
    final i18n = ctx.i18n;
    TextSpan bullet(int n) => TextSpan(children: [
          TextSpan(text: i18n.t('dashboard.howToChooseBullet${n}Title'), style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' ${i18n.t('dashboard.howToChooseBullet${n}Body')}'),
        ]);
    return CollapsibleCard(
      icon: LucideIcons.info,
      title: i18n.t('dashboard.howToChooseTitle'),
      color: ctx.theme.fg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n.t('dashboard.howToChooseDesc'), style: tx(13, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 10),
          for (var n = 1; n <= 4; n++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(bullet(n), style: tx(13, c: Tw.gray600, h: relaxed)),
            ),
        ],
      ),
    );
  }
}

/// Haftanın yedi günü: bugün noktalı, seçili gün dolu. Erişilebilirlik için her gün bir düğmedir.
class WeekDayStrip extends StatelessWidget {
  const WeekDayStrip({super.key, required this.ctx, required this.selected, required this.onSelect});

  final RoutineCtx ctx;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final today = getTurkeyWeekdayIndex();
    return Row(children: [
      for (var d = 0; d < 7 && d < ctx.weekDays.length; d++) ...[
        if (d > 0) const SizedBox(width: 6),
        Expanded(
          child: Semantics(
            button: true,
            selected: d == selected,
            label: ctx.weekDays[d],
            child: Material(
              color: d == selected ? ctx.theme.primary : ctx.theme.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelect(d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        ctx.weekDays[d],
                        style: tx(12.5, w: d == selected ? 7 : 5, c: d == selected ? Colors.white : Tw.gray600),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d == today ? (d == selected ? Colors.white : ctx.theme.primary) : Colors.transparent,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Seyrek / güçlü adımlar: ad, rozetler ve uygulanacak günler (7 küçük kutu).
class WeeklyItemCard extends StatelessWidget {
  const WeeklyItemCard({super.key, required this.item, required this.days, required this.ctx});

  final RoutineItem item;
  final List<int> days;
  final RoutineCtx ctx;

  @override
  Widget build(BuildContext context) {
    final theme = ctx.theme;
    final detail = pickDetail(item, localized: ctx.localized);
    return RCard(
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(pickAction(item, localized: ctx.localized), style: tx(14.5, w: 7, c: Tw.gray800, h: snug)),
          StructuredBadges(item: item),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(12.5, c: Tw.gray500, h: snug)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            for (var d = 0; d < 7 && d < ctx.weekDays.length; d++) ...[
              if (d > 0) const SizedBox(width: 5),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: days.contains(d) ? theme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: days.contains(d) ? theme.primary : Tw.gray200),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(ctx.weekDays[d], style: tx(11.5, w: 6, c: days.contains(d) ? Colors.white : Tw.gray400)),
                  ),
                ),
              ),
            ],
          ]),
          if (days.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              ctx.i18n.t('mobileRoutine.weeklyDays', {'days': days.map((i) => ctx.weekDays[i]).join(', ')}),
              style: tx(12, c: Tw.gray500, h: snug),
            ),
          ],
        ],
      ),
    );
  }
}

/// Yaşam / beslenme önerisi: simge, ad ve açılır ayrıntı.
class LifestyleRow extends StatefulWidget {
  const LifestyleRow({super.key, required this.item, required this.ctx});

  final RoutineItem item;
  final RoutineCtx ctx;

  @override
  State<LifestyleRow> createState() => _LifestyleRowState();
}

class _LifestyleRowState extends State<LifestyleRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.ctx;
    final detail = pickDetail(widget.item, localized: c.localized);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(glyphForEmoji(str(widget.item['icon']), fallback: LucideIcons.leaf), size: 18, color: c.theme.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pickAction(widget.item, localized: c.localized), style: tx(14, w: 6, c: Tw.gray800, h: snug)),
                if (detail.isNotEmpty) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _open = !_open),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          _open ? c.i18n.t('common.hide') : c.i18n.t('dashboard.lifestyleThisItem'),
                          style: tx(12.5, w: 6, c: c.theme.fg),
                        ),
                        const SizedBox(width: 4),
                        Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14, color: c.theme.fg),
                      ]),
                    ),
                  ),
                  if (_open) Text(detail, style: tx(12.5, c: Tw.gray600, h: relaxed)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
