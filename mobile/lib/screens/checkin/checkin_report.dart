import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/daily_tracking.dart';
import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/routine_tracking.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/glyphs.dart';
import '../../ui/shell/page_stage.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'checkin_parts.dart';

/// Check-in raporu (sunucunun `POST /daily_checkin` yanıtı): yapay zekâ notu, rutinde yapılan değişiklikler, bugünün rutini,
/// geri bildirim ve "Bugün'e dön". Sahneyle başlar; her bölüm tek karttır (ilk kart sahneye biner).
/// Geri bildirim durumu (not, gönderildi/atlandı) bu ekrana aittir.
class CheckinReport extends StatefulWidget {
  const CheckinReport({super.key, required this.result, required this.theme});

  final Map<String, dynamic> result;
  final RebiTheme theme;

  @override
  State<CheckinReport> createState() => _CheckinReportState();
}

class _CheckinReportState extends State<CheckinReport> {
  bool _feedbackBusy = false;

  /// null | sent | skipped
  String? _feedbackStatus;
  final _feedbackNote = TextEditingController();

  String? get _uid => context.read<AuthController>().user?.id;

  @override
  void dispose() {
    _feedbackNote.dispose();
    super.dispose();
  }

  Future<void> _sendFeedback(String helpful) async {
    setState(() => _feedbackBusy = true);
    final note = _feedbackNote.text;
    await ingestDailyTrackingEvent(_uid, 'checkin_feedback', {
      'helpful': helpful,
      'note': note.length > 500 ? note.substring(0, 500) : note,
      'source_screen': 'checkin_report',
    });
    if (!mounted) return;
    setState(() {
      _feedbackStatus = 'sent';
      _feedbackBusy = false;
    });
  }

  /// Bugünün rutini anlık görüntüye yazılır (Bugün sekmesi en güncel hâli gösterir) ve Bugün'e dönülür.
  Future<void> _backToDashboard() async {
    final result = widget.result;
    final id = _uid;
    final today = asRoutine(result['today_routine']);
    if (id != null && isRoutineTrackingAccepted(id) && today.isNotEmpty) {
      await saveRoutineSnapshot(id, {...?getRoutineSnapshot(id), 'routine': result['today_routine'], 'checkinResult': result});
    }
    if (!mounted) return;
    context.go('/dashboard', extra: {'routine': result['today_routine'], 'checkinResult': result});
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = widget.theme;
    final result = widget.result;
    final changes = (result['changes'] as List?)?.whereType<Map>().toList() ?? const [];
    final today = asRoutine(result['today_routine']);
    final localized = i18n.prefersLocalized;
    final risk = i18n.t('mobileCheckin.result.risk', {'level': str(result['risk_level'])});
    final subtitle = result['adaptation_type'] == 'major' ? '$risk · ${i18n.t('mobileCheckin.result.major')}' : risk;

    return StagePage(
      theme: theme,
      title: i18n.t('checkin.todayReport'),
      subtitle: subtitle,
      backTo: '/dashboard',
      children: [
        if (truthy(result['ai_note'])) ...[
          RCard(
            leftBorderColor: theme.primary,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.sparkles, size: 20, color: theme.fg)),
                const SizedBox(width: 12),
                Expanded(child: Text(str(result['ai_note']), style: tx(14.5, c: Tw.gray700, h: relaxed))),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (changes.isNotEmpty) ...[
          RCard(
            padding: const EdgeInsets.all(18),
            radius: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckinCardTitle(icon: LucideIcons.circleAlert, color: Tw.amber600, text: i18n.t('mobileCheckin.result.changes')),
                const SizedBox(height: 12),
                for (var i = 0; i < changes.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _ChangeTile(change: changes[i], theme: theme),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (today.isNotEmpty) ...[
          RCard(
            padding: const EdgeInsets.all(18),
            radius: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckinCardTitle(icon: LucideIcons.listChecks, color: theme.fg, text: i18n.t('mobileCheckin.result.todayRoutine')),
                const SizedBox(height: 12),
                for (var i = 0; i < today.take(10).length; i++) ...[
                  if (i > 0) const Divider(height: 20, thickness: 1),
                  _RoutineRow(item: today[i], theme: theme, localized: localized),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_feedbackStatus == null)
          RCard(
            padding: const EdgeInsets.all(18),
            radius: 22,
            margin: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('checkin.feedbackTitle'), style: tx(14, w: 6, c: Tw.gray800, h: snug)),
                const SizedBox(height: 10),
                TextField(
                  controller: _feedbackNote,
                  minLines: 2,
                  maxLines: 3,
                  style: tx(14),
                  decoration: inputDecoration(radius: 14, borderWidth: 1, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _FeedbackButton(
                        border: Tw.emerald200,
                        bg: Tw.emerald50,
                        fg: Tw.emerald900,
                        icon: LucideIcons.thumbsUp,
                        label: 'OK',
                        onTap: _feedbackBusy ? null : () => _sendFeedback('helpful'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FeedbackButton(
                        border: Tw.rose200,
                        bg: Tw.rose50,
                        fg: Tw.rose900,
                        icon: LucideIcons.thumbsDown,
                        onTap: _feedbackBusy ? null : () => _sendFeedback('not_helpful'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: TextButton(
                        onPressed: _feedbackBusy ? null : () => setState(() => _feedbackStatus = 'skipped'),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Tw.gray200)),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: const Size(48, 48),
                        ),
                        child: Text(i18n.t('checkin.feedbackSkip'), style: tx(13, w: 5, c: Tw.gray600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        else if (_feedbackStatus == 'sent')
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(i18n.t('checkin.feedbackThanks'), textAlign: TextAlign.center, style: tx(13, c: Tw.readable(Tw.emerald700))),
          ),
        PrimaryButton(color: theme.primary, label: i18n.t('checkin.backToDashboard'), trailingIcon: LucideIcons.arrowRight, onPressed: _backToDashboard),
      ],
    );
  }
}

/// Rutinde yapılan tek değişiklik: ürün/adım, eski → yeni ve gerekçe.
class _ChangeTile extends StatelessWidget {
  const _ChangeTile({required this.change, required this.theme});

  final Map change;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(Tw.amber50.withValues(alpha: .6), Tw.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tw.amber100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(str(change['item']), style: tx(14, w: 6, c: Tw.gray800)),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${str(change['old'])} → '),
              TextSpan(text: str(change['new']), style: tx(12.5, w: 6, c: theme.fg)),
            ]),
            style: tx(12.5, c: Tw.gray600),
          ),
          const SizedBox(height: 3),
          Text(str(change['reason']), style: tx(12.5, c: Tw.gray600, h: snug)),
        ],
      ),
    );
  }
}

/// Bugünün rutininden bir satır: simge, adım, ayrıntı ve saat.
class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.item, required this.theme, required this.localized});

  final RoutineItem item;
  final RebiTheme theme;
  final bool localized;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(glyphForEmoji(str(item['icon']), fallback: LucideIcons.dot), size: 18, color: Tw.gray600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pickAction(item, localized: localized), style: tx(13.5, w: 6, c: Tw.gray800, h: snug)),
              StructuredBadges(item: item),
              const SizedBox(height: 2),
              Text(pickDetail(item, localized: localized), maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(12, c: Tw.gray600, h: snug)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: theme.primaryLight, borderRadius: BorderRadius.circular(999)),
          child: Text(str(item['time']), style: tx(11, w: 6, c: theme.primaryDark)),
        ),
      ],
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  const _FeedbackButton({required this.border, required this.bg, required this.fg, required this.icon, required this.onTap, this.label});

  final Color border;
  final Color bg;
  final Color fg;
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? .6 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 1.5)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: fg),
                if (label != null) ...[const SizedBox(width: 8), Text(label!, style: tx(14, w: 6, c: fg))],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
