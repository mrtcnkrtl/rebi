import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/interpolate.dart';
import '../tw.dart';
import '../widgets/common.dart';

/// Sorun özelinde klinik şiddet anketi (metinler `severityTests.json`).
/// Web: `components/SeverityTest.jsx`.
class SeverityTest extends StatefulWidget {
  const SeverityTest({super.key, required this.concern, required this.onScoreChange});

  final String concern;
  final ValueChanged<int> onScoreChange;

  @override
  State<SeverityTest> createState() => _SeverityTestState();
}

int calculateSeverityScore(Map<String, num> answers, num maxPossible) {
  final total = answers.values.fold<num>(0, (s, v) => s + v);
  final normalized = (total / maxPossible * 9).round() + 1;
  return normalized.clamp(1, 10).toInt();
}

class _SeverityTestState extends State<SeverityTest> {
  final Map<String, num> _answers = {};

  @override
  Widget build(BuildContext context) {
    final pack = context.i18n.severityTestsPack;
    final ui = Pack((pack['ui'] as Map?)?.cast<String, dynamic>() ?? const {});
    final test = pack[widget.concern];
    if (test is! Map) return const SizedBox.shrink();
    final questions = (test['questions'] as List? ?? const []).whereType<Map>().toList();
    final maxPossible = questions.fold<num>(0, (sum, q) {
      final opts = (q['options'] as List? ?? const []).whereType<Map>();
      final best = opts.map((o) => (o['score'] as num?) ?? 0).fold<num>(-1 << 31, (a, b) => a > b ? a : b);
      return sum + best;
    });

    final answered = _answers.length;
    final total = questions.length;
    final complete = answered == total;
    final score = complete && maxPossible > 0 ? calculateSeverityScore(_answers, maxPossible) : null;

    (String, Color, Color)? severity;
    if (score != null) {
      if (score <= 3) {
        severity = (ui.s('mild'), Tw.green600, Tw.green100);
      } else if (score <= 6) {
        severity = (ui.s('moderate'), Tw.amber600, Tw.amber100);
      } else {
        severity = (ui.s('severe'), Tw.red600, Tw.red100);
      }
    }

    void select(String qId, num optScore) {
      setState(() => _answers[qId] = optScore);
      if (_answers.length == total) widget.onScoreChange(calculateSeverityScore(_answers, maxPossible));
    }

    return RCard(
      borderColor: Tw.teal100,
      color: Color.alphaBlend(Tw.teal50.withValues(alpha: .2), Tw.surface),
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text((test['icon'] ?? '').toString(), style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((test['title'] ?? '').toString(), style: tx(14, w: 7)),
                    Text((test['subtitle'] ?? '').toString(), style: tx(12, c: Tw.gray500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            interpolate(ui.s('answeredProgress'), {'answered': answered, 'total': total}),
            textAlign: TextAlign.right,
            style: tx(12, c: Tw.gray500),
          ),
          for (final q in questions) ...[
            const SizedBox(height: 20),
            Text((q['text'] ?? '').toString(), style: tx(14, w: 5, c: Tw.gray700)),
            const SizedBox(height: 8),
            for (final opt in (q['options'] as List? ?? const []).whereType<Map>()) ...[
              _OptionButton(
                label: (opt['label'] ?? '').toString(),
                selected: _answers.containsKey(q['id']) && _answers[q['id']] == opt['score'],
                questionAnswered: _answers.containsKey(q['id']),
                onTap: () => select(q['id'].toString(), (opt['score'] as num?) ?? 0),
              ),
              const SizedBox(height: 6),
            ],
          ],
          const SizedBox(height: 14),
          if (complete && severity != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: severity.$3, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Text(ui.s('computedScoreLabel'), style: tx(12, c: Tw.gray500)),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text('$score/10', style: tx(30, w: 7, c: severity.$2)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: severity.$3, borderRadius: BorderRadius.circular(999)),
                        child: Text(severity.$1, style: tx(14, w: 6, c: severity.$2)),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Text(ui.s('answerAllHint'), textAlign: TextAlign.center, style: tx(12, c: Tw.gray500)),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.selected,
    required this.questionAnswered,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool questionAnswered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected ? Tw.teal500 : (questionAnswered ? Tw.gray100 : Tw.gray200);
    final bg = selected ? Tw.teal50 : (questionAnswered ? Tw.gray50 : Tw.surface);
    final fg = selected ? Tw.teal800 : (questionAnswered ? Tw.gray400 : Tw.gray700);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? Tw.teal500 : Tw.gray300, width: 2),
                ),
                alignment: Alignment.center,
                child: selected
                    ? Container(width: 8, height: 8, decoration: BoxDecoration(color: Tw.teal500, shape: BoxShape.circle))
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: tx(14, w: selected ? 5 : 4, c: fg))),
            ],
          ),
        ),
      ),
    );
  }
}
