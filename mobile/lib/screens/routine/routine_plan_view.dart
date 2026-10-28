import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/routine_logic.dart';
import '../../ui/brand/palette.dart';
import '../../ui/components/photo_picker.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/stage_overlap.dart';
import 'routine_parts.dart';
import 'routine_stage.dart';

/// Rutin sekmesi (ve analiz sonrası rutini kabul etmeden önceki görünüm): tek sütun, sakin.
///
/// Yukarıdan aşağı: başlık ve kısa profil satırı → (kabul edilmediyse) "kabul et" kartı → sabah kullanım uyarısı ve günlük
/// denge notu → **gün seçici ve seçilen günün sabah/akşam adımları** → seyrek adımlar → check-in → hava ve aktifler →
/// katlanır bölümler (etken madde listesi, nasıl seçersin, yaşam ve beslenme) → ilerleme fotoğrafı.
class RoutinePlanView extends StatefulWidget {
  const RoutinePlanView({
    super.key,
    required this.view,
    required this.merged,
    required this.ctx,
    required this.dateLine,
    required this.userName,
    required this.accepted,
    required this.flashNeedAccept,
    required this.onAccept,
    this.onBackToTracking,
  });

  final RoutineView view;

  /// `routine`, `weather`, `flowDebug`, `checkinResult`, `activePlan`, `photoUrl` içeren birleşik veri.
  final Map<String, dynamic> merged;
  final RoutineCtx ctx;
  final String dateLine;
  final String userName;
  final bool accepted;

  /// Takibe geçmeden gelindi: "önce rutini kabul et" notu.
  final bool flashNeedAccept;
  final VoidCallback onAccept;

  /// Takip görünümüne dönüş bağlantısı (Rutin sekmesinde yok).
  final VoidCallback? onBackToTracking;

  @override
  State<RoutinePlanView> createState() => _RoutinePlanViewState();
}

class _RoutinePlanViewState extends State<RoutinePlanView> {
  /// Gösterilen haftanın günü (0 = Pzt); null ise bugün.
  int? _day;

  RoutineCtx get c => widget.ctx;

  Widget _gap([double h = 16]) => SizedBox(height: h);

  /// Sahnedeki profil etiketleri: cilt tipi · şiddet · yaş grubu (risk düzeyi günlük denge kartında gösterilir).
  List<String> _profileChips(Object? flowDebug) {
    if (flowDebug is! Map) return const [];
    return [str(flowDebug['skin_type']), str(flowDebug['severity']), str(flowDebug['age_group'])].where((s) => s.isNotEmpty).toList();
  }

  Widget _acceptCard() {
    final i18n = c.i18n;
    return RCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      borderColor: c.theme.primaryLight,
      borderWidth: 1.5,
      color: Color.alphaBlend(c.theme.primary.withValues(alpha: .06), Tw.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.theme.primary.withValues(alpha: .14), shape: BoxShape.circle),
                child: Icon(LucideIcons.circleCheck, size: 20, color: c.theme.fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(i18n.t('dashboard.acceptBanner'), style: tx(14.5, w: 5, c: Tw.gray800, h: relaxed)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryButton(color: c.theme.primary, onPressed: widget.onAccept, label: i18n.t('dashboard.acceptCta'), fontSize: 15.5, minHeight: 54),
        ],
      ),
    );
  }

  List<Widget> _dayContent(int d) {
    final v = widget.view;
    final i18n = c.i18n;
    final plan = v.routineByDay[d] ?? const DayPlan([], []);
    final morningNotes = v.wellnessMorningItems;
    final eveningNotes = v.wellnessEveningItems;
    final hints = v.eveningMorningHints;
    final hasMorning = plan.morning.isNotEmpty || morningNotes.isNotEmpty;
    final hasEvening = plan.evening.isNotEmpty || eveningNotes.isNotEmpty;
    if (!hasMorning && !hasEvening) {
      return [
        RCard(
          radius: 22,
          child: Text(i18n.t('dashboard.noPlannedSteps'), style: tx(13.5, c: Tw.gray600, h: relaxed)),
        ),
        if (hints.isNotEmpty) ...[_gap(14), MorningHintsCard(hints: hints, ctx: c)],
      ];
    }
    return [
      if (hasMorning)
        RoutineBlockCard(
          icon: LucideIcons.sun,
          title: i18n.t('dashboard.morning'),
          ctx: c,
          tone: BlockTone.morning,
          steps: plan.morning,
          notes: morningNotes,
          // Akşam etkenlerinin sabah kullanılmaması uyarısı sabah bloğunun içindedir: ilgili yerde, ayrı bir kutu olarak değil.
          footer: hints.isNotEmpty ? MorningHintsCard(hints: hints, ctx: c, inline: true) : null,
        )
      else if (hints.isNotEmpty)
        MorningHintsCard(hints: hints, ctx: c),
      if ((hasMorning || hints.isNotEmpty) && hasEvening) _gap(14),
      if (hasEvening)
        RoutineBlockCard(icon: LucideIcons.moon, title: i18n.t('dashboard.evening'), ctx: c, tone: BlockTone.evening, steps: plan.evening, notes: eveningNotes),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final i18n = c.i18n;
    final theme = c.theme;
    final v = widget.view;
    final merged = widget.merged;
    final flowDebug = merged['flowDebug'];
    final checkinResult = merged['checkinResult'];
    final weather = merged['weather'];
    final activePlan = (merged['activePlan'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final photoUrl = merged['photoUrl'];
    final day = _day ?? getTurkeyWeekdayIndex();

    final todayIdx = getTurkeyWeekdayIndex();
    final dayCaption = day == todayIdx ? '${c.weekDays[day]} · ${i18n.t('dashboard.todayTitle')}' : c.weekDays[day];

    final stage = RoutineStage(
      title: i18n.t('dashboard.myRoutineTitle', {'name': widget.userName}),
      dateLine: widget.dateLine,
      theme: theme,
      chips: _profileChips(flowDebug),
      dayLabel: i18n.t('dashboard.routineByDayTitle'),
      strip: WeekDayStrip(ctx: c, selected: day, onSelect: (d) => setState(() => _day = d), onStage: true),
      caption: dayCaption,
      trailing: widget.onBackToTracking == null
          ? null
          : TextButton(
              onPressed: widget.onBackToTracking,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: Brand.cream),
              child: Text(i18n.t('dashboard.backToTracking'), style: tx(13.5, w: 6, c: Brand.cream)),
            ),
    );

    final body = <Widget>[
      if (widget.flashNeedAccept)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: RCard(
            padding: const EdgeInsets.all(14),
            radius: 20,
            borderColor: Tw.amber200,
            color: Color.alphaBlend(Tw.amber50.withValues(alpha: .8), Tw.surface),
            child: Text(i18n.t('dashboard.acceptHint'), style: tx(13.5, c: Tw.amber900, h: relaxed)),
          ),
        ),
      if (!widget.accepted) ...[_acceptCard(), _gap(16)],
      // Seçilen günün planı (hangi günün açık olduğu sahnedeki başlıkta yazar).
      ..._dayContent(day),
      if (v.dailyBalanceItem != null) ...[_gap(14), DailyBalanceCard(item: v.dailyBalanceItem, flowDebug: flowDebug, ctx: c)],
      if (v.dailyLifestyleItems.isNotEmpty) ...[
        _gap(14),
        CollapsibleCard(
          icon: LucideIcons.leaf,
          title: i18n.t('dashboard.everyDayAllDayTitle'),
          subtitle: i18n.t('mobileRoutine.everyDayCount', {'n': v.dailyLifestyleItems.length}),
          color: theme.fg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(i18n.t('dashboard.everyDayAllDayHint'), style: tx(12, c: Tw.gray500, h: relaxed)),
              _gap(6),
              for (var i = 0; i < v.dailyLifestyleItems.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                LifestyleRow(key: ValueKey('all-days-$i'), item: v.dailyLifestyleItems[i], ctx: c),
              ],
            ],
          ),
        ),
      ],

      if (v.weeklyItems.isNotEmpty) ...[
        RoutineSectionTitle(
          icon: LucideIcons.calendarDays,
          title: i18n.t('dashboard.weeklyTitle'),
          subtitle: i18n.t('dashboard.weeklyHint'),
          color: theme.fg,
        ),
        for (final w in v.weeklyItems) ...[
          WeeklyItemCard(item: w.item, days: w.displayDays, ctx: c),
          _gap(12),
        ],
      ],

      if (widget.accepted) ...[_gap(20), CheckinPromptCard(ctx: c)],
      if (widget.accepted && checkinResult is Map && truthy(checkinResult['ai_note'])) ...[
        _gap(14),
        AiNoteCard(checkinResult: checkinResult, ctx: c, showChanges: true),
      ],

      if (weather is Map && truthy(weather['temperature'])) ...[_gap(20), WeatherLine(weather: weather, ctx: c)],
      if (activePlan.isNotEmpty) ...[_gap(14), ActivePlanCard(activePlan: activePlan, ctx: c)],

      if (v.routineIngredientsList.isNotEmpty) ...[
        _gap(14),
        CollapsibleCard(
          icon: LucideIcons.flaskConical,
          title: i18n.t('dashboard.productListTitle'),
          subtitle: i18n.t('mobileRoutine.ingredientCount', {'n': v.routineIngredientsList.length}),
          color: theme.fg,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in v.routineIngredientsList)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.primaryLight),
                  ),
                  child: Text(name, style: tx(12.5, w: 5, c: theme.primaryDark, h: snug)),
                ),
            ],
          ),
        ),
      ],
      _gap(14),
      HowToChooseCard(ctx: c),

      if (v.nutritionItems.isNotEmpty || v.wellnessItems.isNotEmpty) ...[
        RoutineSectionTitle(
          icon: LucideIcons.leaf,
          title: i18n.t('dashboard.lifestyleSupportsTitle'),
          subtitle: i18n.t('dashboard.lifestyleSupportsSubtitle'),
          color: theme.fg,
        ),
        if (v.nutritionItems.isNotEmpty)
          CollapsibleCard(
            icon: LucideIcons.apple,
            title: i18n.t('dashboard.nutritionTitle'),
            subtitle: i18n.t('mobileRoutine.everyDayCount', {'n': v.nutritionItems.length}),
            color: Tw.emerald700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < v.nutritionItems.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  LifestyleRow(key: ValueKey('n-$i'), item: v.nutritionItems[i], ctx: c),
                ],
              ],
            ),
          ),
        if (v.nutritionItems.isNotEmpty && v.wellnessItems.isNotEmpty) _gap(14),
        if (v.wellnessItems.isNotEmpty)
          CollapsibleCard(
            icon: LucideIcons.heart,
            title: i18n.t('dashboard.mindMovementTitle'),
            subtitle: i18n.t('mobileRoutine.everyDayCount', {'n': v.wellnessItems.length}),
            color: Tw.indigo600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < v.wellnessItems.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  LifestyleRow(key: ValueKey('w-$i'), item: v.wellnessItems[i], ctx: c),
                ],
              ],
            ),
          ),
      ],

      // Su ve uyku: iki kısa not.
      _gap(14),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _tip(LucideIcons.droplet, Tw.blue500, i18n.t('mobileRoutine.tips.water.title'), i18n.t('mobileRoutine.tips.water.body'))),
            const SizedBox(width: 12),
            Expanded(child: _tip(LucideIcons.moon, Tw.indigo500, i18n.t('mobileRoutine.tips.sleep.title'), i18n.t('mobileRoutine.tips.sleep.body'))),
          ],
        ),
      ),

      if (truthy(photoUrl)) ...[_gap(20), _photoCard(str(photoUrl))],
      _gap(24),
      SecondaryButton(
        onPressed: () => context.go('/dashboard/analyze'),
        borderColor: theme.primaryLight,
        textColor: theme.fg,
        icon: LucideIcons.circlePlus,
        label: i18n.t('dashboard.newAnalyzeCta'),
      ),
      // Kalıcı beyan sayfanın başında değil sonunda durur: rutin ilk görülen şeydir.
      const AiDisclaimer(padding: EdgeInsets.only(top: 18)),
    ];

    return ThemedPage(
      theme: theme,
      maxWidth: 672,
      padding: EdgeInsets.zero,
      children: [
        StageOverlap(
          overlap: RoutineStage.overlap,
          stage: stage,
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
          ),
        ),
      ],
    );
  }

  Widget _tip(IconData icon, Color color, String title, String body) => RCard(
        padding: const EdgeInsets.all(14),
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(title, style: tx(13, w: 7, c: Tw.gray800)),
            const SizedBox(height: 2),
            Text(body, style: tx(12, c: Tw.gray500, h: snug)),
          ],
        ),
      );

  Widget _photoCard(String photoUrl) {
    final i18n = c.i18n;
    return RCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(LucideIcons.calendar, size: 16, color: c.theme.fg),
            const SizedBox(width: 8),
            Expanded(child: Text(i18n.t('mobileRoutine.progressPhoto'), style: tx(13, w: 7, c: Tw.gray800))),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 160,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photoFromUrlOrPath(photoUrl, height: 160),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: c.theme.primary, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        '${i18n.t('dashboard.dayLabel', {'n': 1})} · ${DateFormat.yMd(i18n.lang).format(DateTime.now())}',
                        style: tx(11, w: 7, c: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
