import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/glyphs.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import '../analyze/analyze_widgets.dart';
import 'checkin_parts.dart';
import 'checkin_water.dart';

/// Dün gece kaç saat uyudun? (3–12 sa, yarım saat adımlı kaydırıcı).
class CheckinSleepCard extends StatelessWidget {
  const CheckinSleepCard({super.key, required this.hours, required this.onChanged});

  final double hours;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckinCardTitle(icon: LucideIcons.moon, color: Tw.indigo500, text: i18n.t('mobileCheckin.sleep.question')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: RangeSlider1(value: hours, min: 3, max: 12, step: .5, color: Tw.indigo500, onChanged: onChanged)),
              const SizedBox(width: 16),
              SizedBox(
                width: 56,
                child: Text(
                  i18n.t('mobileCheckin.sleep.unit', {'h': jsString(hours)}),
                  textAlign: TextAlign.center,
                  style: tx(18, w: 7, c: Tw.dark ? Tw.indigo400 : Tw.indigo600),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final h in const ['3', '7.5', '12']) Text(i18n.t('mobileCheckin.sleep.unit', {'h': h}), style: tx(11.5, c: Tw.gray500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bugün stres seviyen (1–5, beş yüz simgesi).
class CheckinStressCard extends StatelessWidget {
  const CheckinStressCard({super.key, required this.level, required this.theme, required this.onChanged});

  final int level;
  final RebiTheme theme;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckinCardTitle(icon: LucideIcons.smilePlus, color: Tw.purple500, text: i18n.t('mobileCheckin.stress.question')),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var value = 1; value <= 5; value++) ...[
                if (value > 1) const SizedBox(width: 6),
                Expanded(
                  child: CheckinSelectable(
                    selected: level == value,
                    theme: theme,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                    onTap: () => onChanged(value),
                    child: Column(
                      children: [
                        Icon(stressGlyph(value), size: 24, color: level == value ? theme.fg : Tw.gray500),
                        const SizedBox(height: 4),
                        Text(
                          i18n.t('mobileCheckin.stress.l$value'),
                          textAlign: TextAlign.center,
                          style: tx(11.5, w: level == value ? 6 : 5, c: level == value ? Tw.readable(theme.primaryDark) : Tw.gray600, h: tight),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Cilt hissi seçenekleri: kimlikler sunucuya giden değerlerdir, başlık/açıklama `mobileCheckin.skin.<kimlik>` içindedir.
const checkinSkinFeelingIds = ['iyi', 'kuru', 'yagli', 'kirik', 'irritasyon'];

/// Cildin bugün nasıl hissediyor? (tek seçim; seçilmeden check-in gönderilemez).
class CheckinSkinCard extends StatelessWidget {
  const CheckinSkinCard({super.key, required this.selected, required this.theme, required this.onChanged});

  final String selected;
  final RebiTheme theme;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckinCardTitle(icon: LucideIcons.droplets, color: theme.fg, text: i18n.t('mobileCheckin.skin.question')),
          const SizedBox(height: 12),
          for (final id in checkinSkinFeelingIds) ...[
            CheckinSelectable(
              selected: selected == id,
              theme: theme,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              onTap: () => onChanged(id),
              child: Row(
                children: [
                  Icon(skinFeelingGlyph(id), size: 22, color: selected == id ? theme.fg : Tw.gray500),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i18n.t('mobileCheckin.skin.$id.title'), style: tx(14.5, w: 6, c: Tw.gray800)),
                        Text(i18n.t('mobileCheckin.skin.$id.desc'), style: tx(12.5, c: Tw.gray600)),
                      ],
                    ),
                  ),
                  if (selected == id) Icon(LucideIcons.circleCheckBig, size: 20, color: theme.fg),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Ek belirtiler (isteğe bağlı çoklu seçim).
class CheckinSymptomsCard extends StatelessWidget {
  const CheckinSymptomsCard({super.key, required this.tags, required this.onToggle});

  final List<String> tags;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n.t('checkin.symptomsTitle'), style: tx(14.5, w: 7, c: Tw.gray800, h: snug)),
          const SizedBox(height: 4),
          Text(i18n.t('checkin.symptomsHint'), style: tx(12.5, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (id, key) in const [
                ('redness_diffuse', 'checkin.symptomRedness'),
                ('burning_stinging', 'checkin.symptomBurning'),
                ('flaking_peeling', 'checkin.symptomFlaking'),
                ('acne_flare', 'checkin.symptomAcne'),
              ])
                ChoiceChipBox(
                  label: i18n.t(key),
                  selected: tags.contains(id),
                  activeText: Tw.teal900,
                  inactiveText: Tw.gray600,
                  onTap: () => onToggle(id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aktif ürünlere tepki şiddeti (yalnız cilt "hassas" ya da "irritasyon" iken sorulur; 1–3).
class CheckinReactionSeverityCard extends StatelessWidget {
  const CheckinReactionSeverityCard({super.key, required this.severity, required this.onChanged});

  final int severity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n.t('checkin.reactionSeverityTitle'), style: tx(14.5, w: 7, c: Tw.gray800, h: snug)),
          const SizedBox(height: 4),
          Text(i18n.t('checkin.reactionSeverityHint'), style: tx(12.5, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 8),
          RangeSlider1(value: severity.toDouble(), min: 1, max: 3, step: 1, color: Tw.teal600, onChanged: (v) => onChanged(v.round())),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final n in ['1', '2', '3']) Text(n, style: tx(11.5, c: Tw.gray500))],
          ),
        ],
      ),
    );
  }
}

/// Dünkü rutini uyguladın mı? (Evet / Hayır).
class CheckinRoutineAppliedCard extends StatelessWidget {
  const CheckinRoutineAppliedCard({super.key, required this.applied, required this.theme, required this.onChanged});

  final bool applied;
  final RebiTheme theme;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckinCardTitle(icon: LucideIcons.circleCheckBig, color: Tw.green600, text: i18n.t('mobileCheckin.routineQuestion')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: CheckinYesNo(label: i18n.t('common.yes'), selected: applied, theme: theme, onTap: () => onChanged(true))),
              const SizedBox(width: 12),
              Expanded(child: CheckinYesNo(label: i18n.t('common.no'), selected: !applied, theme: theme, onTap: () => onChanged(false))),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Endişene özel" açıklama kartı (ek sorular analizdeki ana soruna göre seçilir).
class CheckinConcernIntroCard extends StatelessWidget {
  const CheckinConcernIntroCard({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      borderColor: Tw.slate100,
      color: Color.alphaBlend(Tw.slate50.withValues(alpha: .9), Tw.surface),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: i18n.t('mobileCheckin.concernIntro.lead'), style: TextStyle(fontWeight: FontWeight.w600, color: Tw.slate800)),
          TextSpan(text: ' ${i18n.t('mobileCheckin.concernIntro.body')}'),
        ]),
        style: tx(12.5, c: Tw.slate600, h: relaxed),
      ),
    );
  }
}

/// Bugün içtiğin su (ml): alan + bardak karşılığı + hızlı artırma düğmeleri. Alan değişince ana ekran yeniden çizer
/// (denetleyiciyi dinler), bu yüzden kart durumsuzdur.
class CheckinWaterCard extends StatelessWidget {
  const CheckinWaterCard({super.key, required this.controller, required this.theme});

  final TextEditingController controller;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final parsed = parseWaterMlInput(controller.text);
    void bump(int delta) {
      final next = ((parsed ?? 0) + delta).clamp(0, 8000);
      controller.text = '$next';
    }

    Widget smallBtn(String label, VoidCallback onTap, {bool primary = false}) => Material(
          color: primary ? Tw.fillWithWhiteText(theme.primary) : Tw.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primary ? theme.primary : Tw.gray200),
              ),
              // Wrap içinde içeriği kadar geniş olsun (alignment kutuyu tam genişliğe şişirirdi).
              child: Align(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(label, style: tx(13, w: 6, c: primary ? Colors.white : Tw.gray700)),
              ),
            ),
          ),
        );

    final nf = NumberFormat.decimalPattern(i18n.lang);
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckinCardTitle(icon: LucideIcons.droplets, color: Tw.sky500, text: i18n.t('mobileCheckin.water.title')),
          const SizedBox(height: 8),
          Text(i18n.t('mobileCheckin.water.help', {'glass': mlPerGlass}), style: tx(12.5, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: tx(14, w: 5),
            decoration: inputDecoration(
              hint: i18n.t('mobileCheckin.water.placeholder', {'ml': mlPerGlass * 8}),
              suffixText: 'ml',
              radius: 14,
              borderWidth: 1,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
          const SizedBox(height: 6),
          Text(i18n.t('mobileCheckin.water.note'), style: tx(12, c: Tw.gray500, h: snug)),
          if (parsed != null && parsed > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Tw.sky50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.sky100)),
              child: Text('${nf.format(parsed)} ml → ${formatGlassesLabel(parsed)}', style: tx(13, w: 6, c: Tw.sky800)),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              smallBtn(i18n.t('mobileCheckin.water.minus', {'ml': mlPerGlass}), () => bump(-mlPerGlass)),
              smallBtn(i18n.t('mobileCheckin.water.plus', {'ml': mlPerGlass}), () => bump(mlPerGlass), primary: true),
              smallBtn(i18n.t('mobileCheckin.water.half', {'ml': mlPerGlass ~/ 2}), () => bump(mlPerGlass ~/ 2)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bugün makyaj: Evet / Hayır / Atla; "Evet" ise nasıl temizlendi ([removal]: cleanser, double, water, wipe, none).
class CheckinMakeupCard extends StatelessWidget {
  const CheckinMakeupCard({super.key, required this.used, required this.removal, required this.theme, required this.onUsed, required this.onRemoval});

  final bool? used;
  final String removal;
  final RebiTheme theme;

  /// true / false / null (atla).
  final ValueChanged<bool?> onUsed;
  final ValueChanged<String> onRemoval;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckinCardTitle(icon: LucideIcons.palette, color: Tw.rose600, text: i18n.t('mobileCheckin.makeup.title')),
          const SizedBox(height: 8),
          Text(i18n.t('mobileCheckin.makeup.hint'), style: tx(12.5, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: CheckinTri(label: i18n.t('common.yes'), selected: used == true, theme: theme, onTap: () => onUsed(true))),
              const SizedBox(width: 8),
              Expanded(child: CheckinTri(label: i18n.t('common.no'), selected: used == false, theme: theme, onTap: () => onUsed(false))),
              const SizedBox(width: 8),
              Expanded(child: CheckinTri(label: i18n.t('common.skip'), selected: false, theme: theme, plain: true, onTap: () => onUsed(null))),
            ],
          ),
          if (used == true) ...[
            const SizedBox(height: 14),
            Text(i18n.t('mobileCheckin.makeup.how'), style: tx(13, w: 6, c: Tw.gray700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in const ['cleanser', 'double', 'water', 'wipe', 'none'])
                  ChoiceChipBox(
                    label: i18n.t('mobileCheckin.makeup.$id'),
                    selected: removal == id,
                    radius: 12,
                    fontSize: 13,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    activeText: Tw.gray900,
                    inactiveText: Tw.gray600,
                    onTap: () => onRemoval(id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Eklemek istediğin bir şey var mı? (isteğe bağlı not).
class CheckinNotesCard extends StatelessWidget {
  const CheckinNotesCard({super.key, required this.controller, required this.theme});

  final TextEditingController controller;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${i18n.t('mobileCheckin.notes.question')} '),
              TextSpan(text: i18n.t('mobileCheckin.notes.optional'), style: tx(14, c: Tw.gray500)),
            ]),
            style: tx(14.5, w: 7, c: Tw.gray800, h: snug),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            style: tx(14),
            decoration: inputDecoration(hint: i18n.t('mobileCheckin.notes.hint'), radius: 14, borderWidth: 1, focusColor: theme.primary),
          ),
        ],
      ),
    );
  }
}
