import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/glyphs.dart';
import '../../ui/brand/palette.dart';
import '../../ui/components/photo_picker.dart';
import '../../ui/components/skin_type_visual.dart' show SkinTexture;
import '../../ui/tw.dart';
import '../../ui/widgets/app_sheet.dart';
import '../../ui/widgets/common.dart';
import 'analyze_flow.dart';
import 'analyze_form.dart';

/// Sihirbaz sayfalarının ihtiyaç duyduğu ekran durumu ve eylemler (ekran durumu bunu uygular).
abstract class FlowHost {
  BuildContext get context;
  AnalyzeForm get form;
  I18n get i18n;
  Pack get pack;
  Map<String, dynamic> get severityPack;

  /// Görünümü yeniler (bir değişiklik uygular).
  void refresh(VoidCallback change);

  /// Cevabı kaydeder; [advance] true ise kısa bir beklemeden sonra sonraki soruya geçer (tek seçimli sorular).
  void answer(VoidCallback change, {bool advance = true});
  bool get locating;
  String get locationError;
  Future<void> pickDate();
  Future<void> pickPhoto(ImageSource source, CameraDevice camera);
  Future<void> locate();
}

const _smokingAmounts = [0, 1, 5, 15, 25];
const _smokingYears = [0, 2, 5, 10, 20];
const _alcoholFreqs = [0, 1, 3, 5, 7];
const _alcoholAmts = [1, 2, 4, 6];
const _makeupFreqs = [0, 1, 3, 5];
const _makeupRemovals = ['none', 'water', 'cleanser', 'double'];
const _skinOrder = ['oily', 'dry', 'combination', 'normal', 'sensitive'];

String _t(FlowHost h, String key, [Map<String, Object?> vars = const {}]) => h.i18n.t('mobileAnalyze.$key', vars);

String _num(FlowHost h, double v) {
  final s = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  return h.i18n.lang == 'tr' ? s.replaceAll('.', ',') : s;
}

/// Sayfa kimliği → gövde. Kimlikler: basics, gender, hormonal, period, skinType, concerns, primary, zones, flags,
/// sev0…, waterSleep, stressIntro, pss0…, smoking, alcohol, makeup, actives, tolerance, photo, summary.
Widget flowPageBody(String id, FlowHost h) {
  if (id.startsWith('sev')) return _severity(h, int.parse(id.substring(3)));
  if (id.startsWith('pss')) return _pss(h, int.parse(id.substring(3)));
  return switch (id) {
    'basics' => _basics(h),
    'gender' => _gender(h),
    'hormonal' => _hormonal(h),
    'period' => _period(h),
    'skinType' => _skinType(h),
    'concerns' => _concerns(h),
    'primary' => _primary(h),
    'zones' => _zones(h),
    'flags' => _flags(h),
    'waterSleep' => _waterSleep(h),
    'stressIntro' => _stressIntro(h),
    'smoking' => _smoking(h),
    'alcohol' => _alcohol(h),
    'makeup' => _makeup(h),
    'actives' => _actives(h),
    'tolerance' => _tolerance(h),
    'photo' => _photo(h),
    'summary' => _summary(h),
    _ => const SizedBox.shrink(),
  };
}

// ═══ Sen ═══

Widget _basics(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'basics.title'), subtitle: _t(h, 'basics.subtitle')),
      const SizedBox(height: 28),
      FlowField(
        label: h.pack.s('step1.nameLabel'),
        controller: f.name,
        hint: h.pack.s('step1.namePlaceholder'),
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 20),
      FlowField(
        label: h.pack.s('step1.ageLabel'),
        controller: f.age,
        hint: '25',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        textInputAction: TextInputAction.done,
      ),
    ],
  );
}

Widget _gender(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'gender.title'), subtitle: _t(h, 'gender.subtitle')),
      const SizedBox(height: 24),
      ChoiceList(
        children: [
          for (final g in const ['female', 'male', 'other'])
            ChoiceTile(
              title: h.pack.or('gender.$g', g),
              selected: f.gender == g,
              onTap: () => h.answer(() {
                f.gender = g;
                if (g != 'female') {
                  f.hormonalStatus = '';
                  f.lastPeriodDate = '';
                }
              }),
            ),
        ],
      ),
    ],
  );
}

Widget _hormonal(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'hormonal.title'), subtitle: _t(h, 'hormonal.subtitle')),
      const SizedBox(height: 24),
      ChoiceList(
        children: [
          for (final id in const ['regular', 'irregular', 'pregnant', 'menopause'])
            ChoiceTile(title: h.pack.s('step1.hormonal_$id'), selected: f.hormonalStatus == id, onTap: () => h.answer(() => f.hormonalStatus = id)),
        ],
      ),
    ],
  );
}

Widget _period(FlowHost h) {
  final f = h.form;
  final empty = f.lastPeriodDate.isEmpty;
  final date = empty ? '' : DateFormat.yMMMMd(h.i18n.lang).format(DateTime.parse(f.lastPeriodDate));
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'period.title'), subtitle: _t(h, 'period.subtitle')),
      const SizedBox(height: 24),
      Semantics(
        button: true,
        label: empty ? _t(h, 'period.pick') : date,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('flow-date'),
            borderRadius: BorderRadius.circular(18),
            onTap: h.pickDate,
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Tw.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: empty ? Tw.gray200 : _theme(h).primary, width: empty ? 1.4 : 1.8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.calendar, size: 22, color: Tw.gray500),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      empty ? _t(h, 'period.pick') : date,
                      style: tx(17, w: empty ? 4 : 6, c: empty ? Tw.gray500 : Tw.gray900),
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 20, color: Tw.gray400),
                ],
              ),
            ),
          ),
        ),
      ),
      if (f.hormonalStatus == 'regular') ...[
        const SizedBox(height: 20),
        BigStepper(
          icon: LucideIcons.refreshCw,
          color: Tw.pink500,
          label: _t(h, 'period.cycle'),
          valueText: _t(h, 'period.days', {'n': f.cycleLength}),
          value: f.cycleLength.toDouble(),
          min: 21,
          max: 35,
          step: 1,
          onChanged: (v) => h.refresh(() => f.cycleLength = v.round()),
          decreaseLabel: _t(h, 'decrease'),
          increaseLabel: _t(h, 'increase'),
        ),
      ],
    ],
  );
}

/// Temayı bağlamdan okur (sayfa işlevleri bağlamı [FlowHost] üzerinden alır).
RebiTheme _theme(FlowHost h) => h.context.read<ThemeController>().theme;

// ═══ Cildin ═══

Widget _skinType(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'skinType.title'), subtitle: _t(h, 'skinType.subtitle')),
      const SizedBox(height: 24),
      ChoiceList(
        children: [
          for (final id in _skinOrder)
            ChoiceTile(
              title: h.pack.or('skinPicker.$id.label', id),
              description: h.pack.s('skinPicker.$id.desc'),
              leading: SkinTexture(id: id, size: 52),
              selected: f.skinType == id,
              onTap: () => h.answer(() => f.skinType = id),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('flow-skin-guide'),
          onPressed: () => _showSkinGuide(h),
          icon: Icon(LucideIcons.circleHelp, size: 18, color: _theme(h).fg),
          label: Text(_t(h, 'skinType.guide'), style: tx(14.5, w: 6, c: _theme(h).fg)),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ),
    ],
  );
}

void _showSkinGuide(FlowHost h) {
  final p = h.pack;
  Widget block(String titleKey, String descKey, String signKey) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(p.s(titleKey), style: heading(20)),
      const SizedBox(height: 6),
      Text(p.s(descKey), style: tx(14.5, c: Tw.gray600, h: 1.4)),
      const SizedBox(height: 10),
      for (final id in _skinOrder)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${p.s('skinPicker.$id.label')}: ',
                  style: tx(14.5, w: 6, c: Tw.gray800),
                ),
                TextSpan(
                  text: p.s('$signKey.$id'),
                  style: tx(14.5, c: Tw.gray600),
                ),
              ],
            ),
            style: tx(14.5, h: 1.4),
          ),
        ),
    ],
  );
  AppSheet.show<void>(
    h.context,
    title: p.s('skinPicker.guideTitle'),
    body: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        block('skinPicker.morningTitle', 'skinPicker.morningDesc', 'skinPicker.morningSign'),
        const SizedBox(height: 18),
        block('skinPicker.tissueTitle', 'skinPicker.tissueDesc', 'skinPicker.tissueSign'),
        const SizedBox(height: 4),
        FlowNote(text: p.s('skinPicker.tipLine'), icon: LucideIcons.lightbulb),
      ],
    ),
  );
}

Widget _concerns(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'concerns.title'), subtitle: _t(h, 'concerns.subtitle')),
      const SizedBox(height: 24),
      ChoiceList(
        gap: 9,
        children: [
          for (final id in concernIds)
            ChoiceTile(
              title: h.pack.or('concern.$id', id),
              multi: true,
              leading: _GlyphDisc(icon: concernGlyph(id), active: f.concerns.contains(id)),
              selected: f.concerns.contains(id),
              onTap: () => h.refresh(() => f.toggleConcern(id)),
            ),
        ],
      ),
    ],
  );
}

class _GlyphDisc extends StatelessWidget {
  const _GlyphDisc({required this.icon, required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fg = context.watch<ThemeController>().theme.fg;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(shape: BoxShape.circle, color: active ? fg.withValues(alpha: .14) : Tw.gray50),
      child: Icon(icon, size: 20, color: active ? fg : Tw.gray500),
    );
  }
}

Widget _primary(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'primary.title'), subtitle: _t(h, 'primary.subtitle')),
      const SizedBox(height: 24),
      ChoiceList(
        children: [
          for (final id in List<String>.of(f.concerns))
            ChoiceTile(
              title: h.pack.or('concern.$id', id),
              leading: _GlyphDisc(icon: concernGlyph(id), active: f.primaryConcern == id),
              selected: f.primaryConcern == id,
              onTap: () => h.answer(() => f.setPrimary(id)),
            ),
        ],
      ),
    ],
  );
}

Widget _zones(FlowHost h) {
  final f = h.form;
  final concern = h.pack.or('concern.${f.primaryConcern}', f.primaryConcern);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'zones.title'), subtitle: _t(h, 'zones.subtitle', {'concern': concern})),
      const SizedBox(height: 24),
      ChipCloud(
        items: [for (final z in zoneIds) (z, h.pack.or('zone.$z', z))],
        isSelected: f.zones.contains,
        onTap: (z) => h.refresh(() => f.toggleZone(z)),
      ),
    ],
  );
}

Widget _flags(FlowHost h) {
  final f = h.form;
  Widget group(String title, List<(String, String)> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title, style: heading(20, h: 1.2)),
      ),
      ChipCloud(
        items: items,
        isSelected: (k) => f.specialFlags[k] ?? false,
        onTap: (k) => h.refresh(() => f.specialFlags[k] = !(f.specialFlags[k] ?? false)),
      ),
    ],
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'flags.title'), subtitle: _t(h, 'flags.subtitle')),
      const SizedBox(height: 24),
      if (f.hasAgingConcern)
        group(_t(h, 'flags.aging'), [
          ('frown_lines', h.pack.s('step2.aging_frown')),
          ('eye_crows_feet', h.pack.s('step2.aging_crow')),
          ('smile_lines', h.pack.s('step2.aging_smile')),
        ]),
      if (f.hasAgingConcern && f.hasSensitivityConcern) const SizedBox(height: 28),
      if (f.hasSensitivityConcern)
        group(_t(h, 'flags.sensitivity'), [
          ('redness_diffuse', h.pack.s('step2.redness_diffuse')),
          ('redness_acne_marks', h.pack.s('step2.redness_acne_marks')),
          ('cold_sensitive', h.pack.s('step2.cold_sensitive')),
          ('stings_with_products', h.pack.s('step2.stings_products')),
        ]),
    ],
  );
}

Widget _severity(FlowHost h, int index) {
  final f = h.form;
  final concern = f.primaryConcern;
  final questions = severityQuestionsFor(h.severityPack, concern);
  if (index >= questions.length) return const SizedBox.shrink();
  final q = questions[index];
  final qid = q['id'].toString();
  final answers = f.severityAnswers.putIfAbsent(concern, () => {});
  final test = h.severityPack[concern] as Map;
  final options = (q['options'] as List? ?? const []).whereType<Map>().toList();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _t(h, 'severity.caption', {'name': (test['title'] ?? '').toString(), 'n': index + 1, 'total': questions.length}),
        style: tx(13, w: 6, c: _theme(h).fg, ls: .2),
      ),
      const SizedBox(height: 8),
      Semantics(header: true, child: Text((q['text'] ?? '').toString(), style: heading(27, h: 1.2))),
      const SizedBox(height: 24),
      ChoiceList(
        children: [
          for (final o in options)
            ChoiceTile(
              title: (o['label'] ?? '').toString(),
              selected: answers.containsKey(qid) && answers[qid] == o['score'],
              onTap: () => h.answer(() => answers[qid] = (o['score'] as num?) ?? 0),
            ),
        ],
      ),
    ],
  );
}

// ═══ Günlük hayat ═══

Widget _waterSleep(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'life.title'), subtitle: _t(h, 'life.subtitle')),
      const SizedBox(height: 24),
      BigStepper(
        icon: LucideIcons.droplets,
        color: Tw.blue500,
        label: _t(h, 'life.water'),
        valueText: _t(h, 'life.liters', {'n': _num(h, f.waterIntake)}),
        value: f.waterIntake,
        min: .5,
        max: 4,
        step: .5,
        onChanged: (v) => h.refresh(() => f.waterIntake = v),
        decreaseLabel: _t(h, 'decrease'),
        increaseLabel: _t(h, 'increase'),
      ),
      const SizedBox(height: 14),
      BigStepper(
        icon: LucideIcons.moon,
        color: Tw.indigo500,
        label: _t(h, 'life.sleep'),
        valueText: _t(h, 'life.hours', {'n': _num(h, f.sleepHours)}),
        value: f.sleepHours,
        min: 3,
        max: 12,
        step: .5,
        onChanged: (v) => h.refresh(() => f.sleepHours = v),
        decreaseLabel: _t(h, 'decrease'),
        increaseLabel: _t(h, 'increase'),
      ),
    ],
  );
}

Widget _stressIntro(FlowHost h) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'stress.title'), subtitle: _t(h, 'stress.lead')),
      const SizedBox(height: 28),
      FlowNote(text: _t(h, 'stress.note'), icon: LucideIcons.brain),
    ],
  );
}

Widget _pss(FlowHost h, int i) {
  final f = h.form;
  final questions = h.pack.list('pss10');
  if (i >= questions.length) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(_t(h, 'stress.caption', {'n': i + 1, 'total': 10}), style: tx(13, w: 6, c: _theme(h).fg, ls: .2)),
      const SizedBox(height: 8),
      Semantics(header: true, child: Text(questions[i].toString(), style: heading(25, h: 1.25))),
      const SizedBox(height: 24),
      ChoiceList(
        gap: 9,
        children: [
          for (var v = 0; v <= 4; v++)
            ChoiceTile(
              title: _t(h, 'stress.scale.$v'),
              selected: f.pssTouched[i] && f.pssAnswers[i] == v,
              onTap: () => h.answer(() {
                f.pssAnswers[i] = v;
                f.pssTouched[i] = true;
              }),
            ),
        ],
      ),
    ],
  );
}

Widget _smoking(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'smoking.title'), subtitle: _t(h, 'smoking.subtitle')),
      const SizedBox(height: 24),
      ChoiceList(
        gap: 9,
        children: [
          for (final v in _smokingAmounts)
            ChoiceTile(
              title: h.pack.s('smokingAmount.$v'),
              selected: f.smokingPerDay == v,
              onTap: () => h.answer(() {
                f.smokingPerDay = v;
                if (v == 0) f.smokingYears = 0;
              }, advance: v == 0),
            ),
        ],
      ),
      if (f.smokingPerDay > 0) ...[
        SubQuestion(h.pack.s('step2.smokingYears')),
        ChipCloud(
          items: [for (final v in _smokingYears) ('$v', h.pack.s('smokingYears.$v'))],
          isSelected: (id) => f.smokingYears == int.parse(id),
          onTap: (id) => h.refresh(() => f.smokingYears = int.parse(id)),
        ),
      ],
    ],
  );
}

Widget _alcohol(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'alcohol.title'), subtitle: _t(h, 'alcohol.subtitle')),
      const SizedBox(height: 24),
      ChoiceList(
        gap: 9,
        children: [
          for (final v in _alcoholFreqs)
            ChoiceTile(
              title: h.pack.s('alcoholFreq.$v'),
              selected: f.alcoholFreq == v,
              onTap: () => h.answer(() => f.alcoholFreq = v, advance: v == 0),
            ),
        ],
      ),
      if (f.alcoholFreq > 0) ...[
        SubQuestion(h.pack.s('step2.alcoholSession')),
        ChipCloud(
          items: [for (final v in _alcoholAmts) ('$v', h.pack.s('alcoholAmt.$v'))],
          isSelected: (id) => f.alcoholAmt == int.parse(id),
          onTap: (id) => h.refresh(() => f.alcoholAmt = int.parse(id)),
        ),
      ],
    ],
  );
}

Widget _makeup(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'makeup.title'), subtitle: _t(h, 'makeup.subtitle')),
      const SizedBox(height: 24),
      ChoiceList(
        children: [
          for (final v in _makeupFreqs)
            ChoiceTile(
              title: h.pack.s('makeup.frequency.$v'),
              selected: f.makeupFreq == v,
              onTap: () => h.answer(() => f.makeupFreq = v, advance: v == 0),
            ),
        ],
      ),
      if (f.makeupFreq > 0) ...[
        SubQuestion(h.pack.s('step2.makeupRemovalQ')),
        ChipCloud(
          items: [for (final id in _makeupRemovals) (id, h.pack.or('makeup.removal.$id', id))],
          isSelected: (id) => f.makeupRemoval == id,
          onTap: (id) => h.refresh(() => f.makeupRemoval = id),
        ),
      ],
    ],
  );
}

// ═══ Ürünlerin ═══

Widget _actives(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'actives.title'), subtitle: _t(h, 'actives.subtitle')),
      const SizedBox(height: 24),
      ChoiceList(
        children: [
          for (final id in const ['none', 'occasional', 'regular'])
            ChoiceTile(
              title: h.pack.or('activesExperience.$id', id),
              selected: f.activesExperience == id,
              onTap: () => h.answer(() => f.activesExperience = id),
            ),
        ],
      ),
    ],
  );
}

(Color, Color) _toleranceColors(String level) => switch (level) {
  'never' => (Tw.gray50, Tw.gray600),
  'good' => (Tw.emerald50, Tw.emerald800),
  'mild' => (Tw.amber50, Tw.amber900),
  _ => (Tw.red50, Tw.red700),
};

Widget _tolerance(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'tolerance.title'), subtitle: _t(h, 'tolerance.subtitle')),
      const SizedBox(height: 20),
      Container(
        decoration: BoxDecoration(
          color: Tw.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Tw.gray100),
        ),
        child: Column(
          children: [
            for (var i = 0; i < strongActiveFamilyIds.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: Tw.gray100, indent: 16, endIndent: 16),
              _ToleranceRow(host: h, family: strongActiveFamilyIds[i], level: f.activesTolerance[strongActiveFamilyIds[i]] ?? 'good'),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      FlowNote(text: h.pack.s('modal.toleranceExplBody')),
    ],
  );
}

class _ToleranceRow extends StatelessWidget {
  const _ToleranceRow({required this.host, required this.family, required this.level});

  final FlowHost host;
  final String family;
  final String level;

  @override
  Widget build(BuildContext context) {
    final name = host.pack.or('strongFamily.$family', family);
    final state = _t(host, 'tolerance.short.$level');
    final (bg, fg) = _toleranceColors(level);
    // Büyük yazıda ad ve durum alt alta dizilir (dar ekranda ad bir harfe sıkışmasın).
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final nameText = Text(name, style: tx(15.5, w: 5, c: Tw.gray800, h: 1.25));
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(state, style: tx(13, w: 6, c: fg)),
    );
    final chevron = Icon(LucideIcons.chevronRight, size: 18, color: Tw.gray400);
    return Semantics(
      button: true,
      label: '$name, $state',
      excludeSemantics: true,
      child: InkWell(
        key: Key('tol-$family'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showToleranceSheet(host, family),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    nameText,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: pill),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: nameText),
                    const SizedBox(width: 12),
                    pill,
                    const SizedBox(width: 4),
                    chevron,
                  ],
                ),
        ),
      ),
    );
  }
}

void _showToleranceSheet(FlowHost h, String family) {
  final f = h.form;
  AppSheet.show<void>(
    h.context,
    title: h.pack.or('strongFamily.$family', family),
    subtitle: _t(h, 'tolerance.sheet'),
    body: (ctx) => ChoiceList(
      children: [
        for (final lv in toleranceLevels)
          ChoiceTile(
            key: Key('tol-$family-$lv'),
            title: h.pack.or('tolerance.$lv', lv),
            selected: f.activesTolerance[family] == lv,
            onTap: () {
              h.refresh(() => f.activesTolerance[family] = lv);
              Navigator.of(ctx).pop();
            },
          ),
      ],
    ),
  );
}

// ═══ Son adım ═══

Widget _photo(FlowHost h) {
  final f = h.form;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: _t(h, 'photo.title'), subtitle: _t(h, 'photo.subtitle')),
      const SizedBox(height: 24),
      PhotoPickerCard(
        photo: f.photo,
        photoContext: f.photoContext,
        changeLabel: h.pack.s('step4.changePhoto'),
        onPick: (s, c) => h.pickPhoto(s, c),
        onClear: () => h.refresh(() => f.photo = null),
        onContextChanged: (v) => h.refresh(() => f.photoContext = v),
      ),
      const SizedBox(height: 18),
      FlowNote(text: f.photo == null ? _t(h, 'photo.tip') : _t(h, 'photo.stored'), icon: f.photo == null ? LucideIcons.sun : LucideIcons.lock),
    ],
  );
}

Widget _summary(FlowHost h) {
  final f = h.form;
  final name = f.name.text.trim();
  final score = f.severityScore(h.severityPack);
  final concernNames = f.concerns.isEmpty ? h.pack.s('concern.general') : f.concerns.map((c) => h.pack.or('concern.$c', c)).join(', ');
  String? severityText;
  if (score != null) {
    final ui = Pack((h.severityPack['ui'] as Map?)?.cast<String, dynamic>() ?? const {});
    final label = score <= 3 ? ui.s('mild') : (score <= 6 ? ui.s('moderate') : ui.s('severe'));
    severityText = '$score/10 · $label';
  }
  final rows = <(String, String)>[
    (_t(h, 'summary.age'), f.age.text.trim()),
    (_t(h, 'summary.skin'), f.skinType.isEmpty ? '—' : h.pack.or('skinPicker.${f.skinType}.label', f.skinType)),
    (_t(h, 'summary.focus'), concernNames),
    if (severityText != null) (_t(h, 'summary.severity'), severityText),
    (_t(h, 'summary.photo'), f.photo == null ? _t(h, 'summary.photoNone') : _t(h, 'summary.photoAdded')),
  ];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(title: name.isEmpty ? _t(h, 'summary.titleNoName') : _t(h, 'summary.title', {'name': name}), subtitle: _t(h, 'summary.lead')),
      const SizedBox(height: 24),
      Container(
        decoration: BoxDecoration(
          color: Tw.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Tw.gray100),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: Tw.gray100, indent: 18, endIndent: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1.5),
                        child: Text(rows[i].$1, style: tx(14, c: Tw.gray500, h: 1.3)),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        rows[i].$2,
                        textAlign: TextAlign.right,
                        style: tx(15.5, w: 6, c: Tw.gray900, h: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      _LocationRow(host: h),
      const SizedBox(height: 20),
      const AiDisclaimer(),
    ],
  );
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.host});

  final FlowHost host;

  @override
  Widget build(BuildContext context) {
    final f = host.form;
    final theme = context.watch<ThemeController>().theme;
    final set = f.locationSet;
    return Semantics(
      button: !set,
      label: set ? _t(host, 'summary.locationSet') : '${_t(host, 'summary.location')}. ${_t(host, 'summary.locationHint')}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('flow-location'),
          borderRadius: BorderRadius.circular(18),
          onTap: set || host.locating ? null : host.locate,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: set ? Color.alphaBlend(theme.primary.withValues(alpha: .08), Tw.surface) : Tw.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: set ? theme.primary : Tw.gray200, width: set ? 1.8 : 1.4),
            ),
            child: Row(
              children: [
                Icon(set ? LucideIcons.circleCheck : LucideIcons.mapPin, size: 22, color: set ? theme.fg : Tw.gray500),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(set ? _t(host, 'summary.locationSet') : _t(host, 'summary.location'), style: tx(15.5, w: 6, c: Tw.gray900)),
                      if (!set) ...[
                        const SizedBox(height: 2),
                        Text(
                          host.locationError.isNotEmpty ? host.locationError : _t(host, 'summary.locationHint'),
                          style: tx(13.5, c: host.locationError.isNotEmpty ? Tw.red600 : Tw.gray500, h: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
                if (host.locating)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                else if (!set)
                  Icon(LucideIcons.chevronRight, size: 18, color: Tw.gray400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
