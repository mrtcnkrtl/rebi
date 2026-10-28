import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../state/today_actions.dart';
import '../../state/today_plan_controller.dart';
import '../../ui/tw.dart';
import 'today_clock.dart';

/// Ekranın altında sabit duran iki düğme: öne çıkan rutini "yaptım" ve "ürün bitti".
/// Üstünde son kaydın onayı (ve varsa "Geri al") görünür.
class TodayActionBar extends StatefulWidget {
  const TodayActionBar({super.key, required this.actions, required this.theme, required this.onProductFinished});

  final TodayActions actions;
  final RebiTheme theme;
  final VoidCallback onProductFinished;

  @override
  State<TodayActionBar> createState() => _TodayActionBarState();
}

class _TodayActionBarState extends State<TodayActionBar> {
  bool _busy = false;

  Future<void> _markDone(String block, bool done) async {
    if (_busy) return;
    final i18n = I18n.instance;
    final actions = widget.actions;
    if (done) {
      // Yanlış dokunuşla bozulmasın: tamamlanmış rutini yeniden açmak için geri al çıkar.
      actions.showToast(
        i18n.t('mobileToday.toast.blockAlreadyDone'),
        undoLabel: i18n.t('mobileToday.toast.reopen'),
        undo: () async {
          final outcome = await actions.log('routine_completed_block', {block: false});
          actions.showToast(i18n.t(outcome == LogOutcome.failed ? 'mobileToday.toast.failed' : 'mobileToday.toast.undone'));
        },
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await actions.record(
        'routine_completed_block',
        {block: true},
        message: i18n.t('mobileToday.toast.blockDone.$block'),
        undoPayload: {block: false},
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.actions, widget.actions.plan, I18n.instance]),
      builder: (context, _) {
        final i18n = I18n.instance;
        final theme = widget.theme;
        final block = widget.actions.blockAt(todayPanelClock());
        final done = widget.actions.plan.plan?.progress.blockDone(block) ?? false;
        final toast = widget.actions.toast;

        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, .3), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: toast == null
                      ? const SizedBox.shrink(key: ValueKey('no-toast'))
                      : _ToastBubble(key: ValueKey(toast), toast: toast, onDismiss: widget.actions.dismissToast),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Tw.surface.withValues(alpha: .98),
                    border: Border(top: BorderSide(color: Tw.gray100)),
                    boxShadow: const [BoxShadow(color: Color(0x0F0B3D38), blurRadius: 20, offset: Offset(0, -6))],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _BarButton(
                          label: i18n.t(done ? 'mobileToday.bar.done.$block' : 'mobileToday.bar.mark.$block'),
                          icon: done ? LucideIcons.circleCheck : LucideIcons.check,
                          filled: !done,
                          color: done ? Tw.emerald700 : theme.fg,
                          fill: theme.primary,
                          loading: _busy,
                          onTap: () => _markDone(block, done),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _BarButton(
                          label: i18n.t('mobileToday.productFinished'),
                          icon: LucideIcons.packageCheck,
                          filled: false,
                          color: theme.fg,
                          onTap: widget.onProductFinished,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.color,
    required this.onTap,
    this.fill,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final bool filled;

  /// Metin, ikon ve çerçeve rengi (koyu modda okunur ton).
  final Color color;

  /// Dolu düğmenin zemini (verilmezse [color]); üstüne beyaz yazı yazılır.
  final Color? fill;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: filled ? (fill ?? color) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: loading ? null : onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: filled ? null : Border.all(color: color.withValues(alpha: .45), width: 1.5),
            ),
            child: Center(
              child: loading
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: fg),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(label, maxLines: 1, style: tx(14, w: 7, c: fg)),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastBubble extends StatelessWidget {
  const _ToastBubble({super.key, required this.toast, required this.onDismiss});

  final TodayToast toast;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Tw.gray800,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: Row(
              children: [
                Expanded(child: Text(toast.message, style: tx(13, w: 5, c: Colors.white, h: snug))),
                if (toast.undo != null)
                  TextButton(
                    onPressed: () {
                      final undo = toast.undo;
                      onDismiss();
                      undo?.call();
                    },
                    child: Text(toast.undoLabel ?? '', style: tx(13, w: 7, c: Tw.teal300)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
