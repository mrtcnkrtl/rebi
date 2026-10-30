import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/demo_user.dart';
import '../core/i18n.dart';
import '../core/shelf.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../state/today_plan_controller.dart';
import '../ui/brand/palette.dart';
import '../ui/shell/page_stage.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/skeleton.dart';
import 'today/today_widgets.dart';

/// Rafım: "ürün bitti" işaretlenip yenisi alınmamış ürünler. Her ürün için "Aldım" (rafa geri döner) ve
/// "Yerine ne kullanabilirim?" (bugünün bağlamıyla sohbete gider). Durum sunucuda olaylardan türetilir; çevrimdışıyken
/// yapılan işaretler kuyruğa alınır ve ekranda hemen görünür.
class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key});

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  TodayPlanController? _controller;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.read<AuthController>().user?.id;
    // Demo oturumunda sunucu verisi yok: boş raf gösterilir.
    if (_controller == null && uid != null && uid != demoUserId) {
      _controller = TodayPlanController(userId: uid)..load(useLocation: false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toast(String message, {String? undoLabel, VoidCallback? undo}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: Duration(seconds: undo == null ? 3 : 6),
        action: undo == null ? null : SnackBarAction(label: undoLabel ?? '', onPressed: undo),
      ));
  }

  Future<void> _restock(ShelfItem item) async {
    final c = _controller;
    if (c == null || _busy) return;
    final i18n = I18n.instance;
    setState(() => _busy = true);
    final payload = <String, dynamic>{
      'product': shelfName(item.product),
      'step_order': ?item.stepOrder,
    };
    try {
      final outcome = await c.log(shelfRestockedEvent, payload);
      if (!mounted) return;
      if (!outcome.saved) {
        _toast(i18n.t('mobileToday.toast.failed'));
        return;
      }
      _toast(
        outcome == LogOutcome.queued ? i18n.t('mobileToday.queuedHint') : i18n.t('mobileToday.toast.restocked', {'product': item.product}),
        undoLabel: i18n.t('mobileToday.toast.undo'),
        undo: () => c.log(shelfFinishedEvent, payload),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _askForAlternative(ShelfItem item) {
    final prompt = I18n.instance.t('mobileShelf.alternativePrompt', {'product': item.product});
    context.go('/dashboard/chat', extra: {'prompt': prompt});
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final c = _controller;

    return StagePage(
      theme: theme,
      title: i18n.t('mobileShelf.title'),
      subtitle: i18n.t('mobileShelf.subtitle'),
      backTo: '/dashboard',
      onRefresh: c?.reload,
      children: [
        if (c == null)
          _empty(i18n)
        else
          ListenableBuilder(listenable: Listenable.merge([c, I18n.instance]), builder: (context, _) => _content(i18n, theme, c)),
      ],
    );
  }

  Widget _content(I18n i18n, RebiTheme theme, TodayPlanController c) {
    final plan = c.plan;
    if (plan == null) {
      if (c.loading) return const Column(children: [SkeletonCard(lines: 2, withActions: true), SizedBox(height: 10), SkeletonCard(lines: 2, withActions: true)]);
      if (c.failed) return _failed(i18n, theme, c);
      return const SizedBox.shrink();
    }
    final items = plan.productsOut;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty)
          _empty(i18n)
        else ...[
          for (final item in items) ...[_itemCard(i18n, theme, item), const SizedBox(height: 10)],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(i18n.t('mobileShelf.hint'), style: tx(12, c: Tw.gray500, h: relaxed)),
          ),
        ],
        if (c.pendingCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(i18n.t('mobileShelf.pending', {'count': c.pendingCount}), style: tx(12, c: Tw.readable(Tw.amber700))),
          ),
      ],
    );
  }

  Widget _itemCard(I18n i18n, RebiTheme theme, ShelfItem item) {
    final age = shelfAge(item);
    return RCard(
      padding: const EdgeInsets.all(18),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TodayIconBadge(icon: LucideIcons.packageX, color: Tw.amber700, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.product, style: tx(16, w: 7, c: Tw.gray900, h: snug)),
                    const SizedBox(height: 3),
                    Text(i18n.t('mobileShelf.age.${age.kind}', {'n': age.days}), style: tx(12.5, c: Tw.gray600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TodayPill(
                label: i18n.t('mobileShelf.restocked'),
                icon: LucideIcons.check,
                color: theme.primary,
                filled: true,
                onTap: _busy ? null : () => _restock(item),
              ),
              TodayPill(
                label: i18n.t('mobileShelf.alternative'),
                icon: LucideIcons.messageCircle,
                color: theme.fg,
                onTap: () => _askForAlternative(item),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(I18n i18n) => RCard(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        radius: 24,
        child: Column(
          children: [
            TodayIconBadge(icon: LucideIcons.packageCheck, color: Tw.emerald700, size: 56),
            const SizedBox(height: 16),
            Text(i18n.t('mobileShelf.emptyTitle'), textAlign: TextAlign.center, style: heading(22)),
            const SizedBox(height: 8),
            Text(i18n.t('mobileShelf.emptyBody'), textAlign: TextAlign.center, style: tx(13, c: Tw.gray600, h: relaxed)),
          ],
        ),
      );

  Widget _failed(I18n i18n, RebiTheme theme, TodayPlanController c) => RCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        borderColor: Tw.amber200,
        color: Color.alphaBlend(Tw.amber50.withValues(alpha: .6), Tw.surface),
        child: Row(children: [
          Icon(LucideIcons.wifiOff, size: 18, color: Tw.amber600),
          const SizedBox(width: 10),
          Expanded(child: Text(i18n.t('mobileShelf.loadFailed'), style: tx(12, c: Tw.amber900))),
          TextLink(i18n.t('mobileShelf.retry'), onTap: c.reload, style: tx(12, w: 6, c: theme.fg)),
        ]),
      );
}
