import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/chat_suggestions.dart';
import '../core/consent_recovery.dart';
import '../core/demo_user.dart';
import '../core/device_location.dart';
import '../core/i18n.dart';
import '../core/subscription.dart';
import '../core/local_store.dart';
import '../core/routine_tracking.dart';
import '../core/today_plan.dart';
import '../state/auth_controller.dart';
import '../state/home_sync_controller.dart';
import '../state/theme_controller.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';

String _historyKey(String userId) => 'rebi-chat-history_$userId';

String _importedKey(String userId) => 'rebi-chat-imported-v1_$userId';

String _usageKey(String userId) => 'rebi-chat-usage_$userId';

typedef ChatMessage = Map<String, String>;

List<ChatMessage> loadChatHistory(String userId) {
  final v = LocalStore.instance.getJson(_historyKey(userId));
  if (v is! List) return [];
  final msgs = v
      .whereType<Map>()
      .map((m) => {'role': '${m['role'] ?? ''}', 'content': '${m['content'] ?? ''}'})
      .toList();
  return msgs.any((m) => m['role'] == 'user') ? msgs : [];
}

/// Sunucu öncesi dönemden kalan yerel sohbeti bir kez yukarı taşı.
Future<void> _importLocalHistory(String userId) async {
  if (LocalStore.instance.getString(_importedKey(userId)) == '1') return;
  final local = loadChatHistory(userId)
      .where((m) => (m['role'] == 'user' || m['role'] == 'assistant') && (m['content'] ?? '').trim().isNotEmpty)
      .toList();
  await LocalStore.instance.setString(_importedKey(userId), '1');
  if (local.isEmpty) return;
  try {
    await apiPost('/chat/history/import', {'user_id': userId, 'messages': local, 'surface': 'general'}, timeout: apiLongTimeout);
  } catch (_) {
    /* çevrimdışı: yerel geçmiş yerinde kalır */
  }
}

class _Usage {
  const _Usage(this.kind, this.remaining, this.limit, this.period);

  final String kind;
  final Object? remaining;
  final Object? limit;
  final String? period;

  Map<String, dynamic> toJson() => {'kind': kind, 'remaining': remaining, 'limit': limit, 'period': period};

  static _Usage? fromJson(Object? v) {
    if (v is! Map || v['kind'] == null) return null;
    return _Usage(v['kind'].toString(), v['remaining'], v['limit'], v['period']?.toString());
  }
}

/// Rebi sohbeti (web: `pages/Chat.jsx`). `/rebi` (anonim) ve `/dashboard/chat` aynı ekranı kullanır.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final AuthController _auth = context.read<AuthController>();

  late String _effectiveUserId;
  List<ChatMessage> _history = [];
  late String _historyOwnerId;

  /// Bu oturumda mesaj gönderildiyse sunucu geçmişi üzerine yazmaz.
  bool _sentThisSession = false;
  bool _loading = false;
  _Usage? _usage;
  bool _paywallOpen = false;
  String _paywallKind = 'free_daily';
  Map<String, dynamic>? _routineSnap;
  bool _routineAccepted = false;
  bool _edgeOpen = false;
  int _generation = 0;

  /// Bugünün planı; öneri çipleri buradan çıkar. Plan yoksa genel sorular gösterilir.
  TodayPlan? _plan;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _effectiveUserId = _auth.user?.id ?? demoUserId;
    _history = loadChatHistory(_effectiveUserId);
    _historyOwnerId = _effectiveUserId;
    _auth.addListener(_onAuthChanged);
    _loadForUser();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Kullanıcı değişince (çıkış/giriş) ekran sıfırlanır.
  void _onAuthChanged() {
    final next = _auth.user?.id ?? demoUserId;
    if (next == _effectiveUserId) return;
    setState(() {
      _effectiveUserId = next;
      _sentThisSession = false;
      _history = loadChatHistory(next);
      _historyOwnerId = next;
      _usage = null;
      _paywallOpen = false;
      _paywallKind = 'free_daily';
      _routineSnap = null;
      _routineAccepted = false;
      _edgeOpen = false;
      _plan = null;
    });
    _loadForUser();
  }

  void _loadForUser() {
    final gen = ++_generation;
    _loadServerHistory(gen);
    _loadUsage(gen);
    _loadSuggestions(gen);
  }

  void _setHistory(List<ChatMessage> next) {
    setState(() => _history = next);
    _persistHistory();
    _scrollToEnd();
  }

  void _persistHistory() {
    if (_historyOwnerId != _effectiveUserId) return;
    if (_history.any((m) => m['role'] == 'user')) {
      final tail = _history.length > 30 ? _history.sublist(_history.length - 30) : _history;
      LocalStore.instance.setJson(_historyKey(_effectiveUserId), tail);
    } else {
      LocalStore.instance.remove(_historyKey(_effectiveUserId));
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  /// Sunucudaki geçmiş: web ve mobil aynı konuşmayı görür.
  Future<void> _loadServerHistory(int gen) async {
    final uid = _auth.user?.id;
    if (uid == null) return;
    try {
      final r = await apiGet('/chat/history', query: {'user_id': uid, 'surface': 'general', 'limit': '50'});
      if (!r.ok || gen != _generation || !mounted) return;
      final messages = (r.data['messages'] as List?)?.whereType<Map>().toList() ?? const [];
      if (messages.isEmpty) {
        await _importLocalHistory(uid);
        return;
      }
      if (_sentThisSession) return;
      setState(() => _historyOwnerId = uid);
      _setHistory([
        for (final m in messages) {'role': '${m['role'] ?? ''}', 'content': '${m['content'] ?? ''}'},
      ]);
    } catch (_) {
      /* çevrimdışı: yerel geçmişle devam */
    }
  }

  /// Bugünün planını (hava, makyaj, beslenme, su) alır; konum izni varsa canlı hava istenir.
  /// Oturum yoksa ya da plan alınamazsa genel öneriler kalır.
  Future<void> _loadSuggestions(int gen) async {
    final uid = _auth.user?.id;
    if (uid == null || uid == demoUserId) return;
    try {
      final locationAllowed = context.read<HomeSyncController>().snapshot?.consent.locationAllowed == true;
      final at = locationAllowed ? await lookupDeviceLocation() : null;
      final plan = await fetchTodayPlan(uid, lat: at?.lat, lon: at?.lon);
      if (plan != null && mounted && gen == _generation) setState(() => _plan = plan);
    } catch (_) {
      /* öneriler genel kalır */
    }
  }

  Future<void> _loadUsage(int gen) async {
    final uid = _effectiveUserId;
    final cached = _Usage.fromJson(LocalStore.instance.getJson(_usageKey(uid)));
    if (cached != null) setState(() => _usage = cached);
    if (_auth.user != null) {
      setState(() {
        _routineAccepted = isRoutineTrackingAccepted(uid);
        _routineSnap = getRoutineSnapshot(uid);
      });
    }
    try {
      final r = await apiGet('/chat_usage', query: {'user_id': uid}, auth: _auth.user != null);
      if (!r.ok || gen != _generation || !mounted) return;
      final d = r.data;
      if (d['kind'] == null || d['kind'] == 'none') return;
      final next = _Usage(d['kind'].toString(), d['remaining'], d['limit'], d['period']?.toString());
      setState(() => _usage = next);
      LocalStore.instance.setJson(_usageKey(uid), next.toJson());
    } catch (_) {
      /* ağ / oturum */
    }
  }

  void _applyUsage(Map<String, dynamic> data) {
    final uid = _auth.user?.id;
    _Usage? next;
    if (data['usage_kind'] != null) {
      final kind = data['usage_kind'].toString();
      next = _Usage(
        kind,
        data['usage_remaining'],
        data['usage_limit'],
        kind == 'plus_monthly' ? 'month' : (kind == 'free_daily' ? 'day' : null),
      );
    } else if (data['free_chat_remaining'] != null && data['free_chat_limit'] != null) {
      next = _Usage('free_daily', data['free_chat_remaining'], data['free_chat_limit'], 'day');
    }
    setState(() => _usage = next);
    if (next != null && uid != null) LocalStore.instance.setJson(_usageKey(uid), next.toJson());
  }

  /// Öneri çipine dokunulursa [preset] gönderilir (yazı alanına dokunulmaz).
  Future<void> _send([String? preset]) async {
    final msg = (preset ?? _input.text).trim();
    if (msg.isEmpty || _loading || _paywallOpen) return;
    if (preset == null) _input.clear();
    _sentThisSession = true;
    final newHist = [..._history, {'role': 'user', 'content': msg}];
    _setHistory(newHist);
    setState(() => _loading = true);
    _scrollToEnd();
    final gen = _generation;
    try {
      final res = await apiPost('/chat_general', {
        'user_id': _auth.user?.id ?? demoUserId,
        'message': msg,
        'history': newHist,
        'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      }, timeout: apiLongTimeout);
      if (!mounted || gen != _generation) return;
      final data = res.data;
      if (!res.ok) {
        if (isConsentError(res.status, data)) {
          // Rıza kaydı yok: kullanıcıyı çıkışa zorlamadan onay kutusunu aç.
          requestConsentRecovery();
          _setHistory([...newHist, {'role': 'assistant', 'content': I18n.instance.t('common.consentRecoveryBody')}]);
          return;
        }
        var errText = '${formatApiErrorDetail(data)} (${res.status})';
        if (res.status == 401) {
          errText = 'Oturum süresi doldu veya giriş doğrulanamadı. Çıkış yapıp tekrar giriş yapmayı dene. $errText';
        }
        if (res.status == 502 || res.status == 503) {
          errText = 'Sunucu geçici olarak yanıt vermiyor. Biraz sonra tekrar dene. $errText';
        }
        _setHistory([...newHist, {'role': 'assistant', 'content': 'Şu an yanıt alınamadı: $errText'}]);
        return;
      }
      _applyUsage(data);
      if (data['chat_quota_exceeded'] == true) {
        setState(() {
          _paywallKind = data['usage_kind'] == 'plus_monthly' ? 'plus_monthly' : 'free_daily';
          _paywallOpen = true;
        });
      }
      final reply = data['reply'] is String ? data['reply'] as String : formatApiErrorDetail(data);
      _setHistory([...newHist, {'role': 'assistant', 'content': reply}]);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      _setHistory([
        ...newHist,
        {
          'role': 'assistant',
          'content': isNetworkError(e)
              ? 'Bağlantı kurulamadı. İnternetini ve API adresini kontrol et; backend çalışıyor mu?'
              : 'Bir hata oluştu, tekrar dener misin?',
        },
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearChat() async {
    _setHistory([]);
    setState(() => _paywallOpen = false);
    await LocalStore.instance.remove(_historyKey(_effectiveUserId));
    final uid = _auth.user?.id;
    if (uid == null) return;
    // Sunucudan da sil; aksi halde mobilde veya yeniden girişte geri gelir.
    try {
      await apiDelete('/chat/history', query: {'user_id': uid});
    } catch (_) {
      /* çevrimdışı: sonraki temizlemede silinir */
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final user = context.watch<AuthController>().user;
    final hasConversation = _history.any((m) => m['role'] == 'user');
    final subscribeHref = user != null ? '/dashboard/subscribe' : '/auth?next=${Uri.encodeComponent('/dashboard/subscribe')}';
    final wide = MediaQuery.of(context).size.width >= 640;

    final routineItems = _routineSnap?['routine'];
    final routineHasItems = routineItems is List && routineItems.isNotEmpty;
    final routineCorner = user == null
        ? null
        : routineHasItems
            ? (
                i18n.t('chat.cornerRoutineReadyTitle'),
                _routineAccepted ? i18n.t('chat.cornerRoutineAcceptedBody') : i18n.t('chat.cornerRoutineDraftBody'),
                '/dashboard',
                i18n.t('chat.cornerRoutineCta'),
              )
            : (
                i18n.t('chat.cornerRoutineMissingTitle'),
                i18n.t('chat.cornerRoutineMissingBody'),
                '/dashboard/analyze',
                i18n.t('chat.cornerRoutineMissingCta'),
              );

    final u = _usage;
    String? cornerUsageText;
    if (u?.kind == 'free_daily' && u?.remaining != null && u?.limit != null) {
      cornerUsageText = i18n.t('chat.usageBadgeDay', {'rem': u!.remaining, 'lim': u.limit});
    } else if (u?.kind == 'plus_monthly' && u?.remaining != null && u?.limit != null) {
      cornerUsageText = i18n.t('chat.usageBadgeMonth', {'rem': u!.remaining, 'lim': u.limit});
    } else if (u?.kind == 'plus_unlimited') {
      cornerUsageText = i18n.t('chat.usageBadgeUnlimited');
    }

    return ThemedBackground(
      theme: theme,
      child: Stack(
        children: [
          CenteredBox(
            maxWidth: 672,
            child: Column(
              children: [
                _header(i18n, theme, hasConversation),
                Expanded(child: hasConversation ? _messages(theme) : _empty(i18n, theme)),
                if (hasConversation) _suggestionStrip(i18n, theme),
                _inputBar(i18n, theme, subscribeHref),
              ],
            ),
          ),
          // Web'de köşe sayacı masaüstü içindir; telefonda aynı rozet başlıkta zaten var.
          if (cornerUsageText != null && wide)
            Positioned(
              top: 76,
              right: 16,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Tw.surface.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Tw.gray200.withValues(alpha: .8)),
                    boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
                  ),
                  child: Text(cornerUsageText, style: tx(11, w: 6, c: Tw.gray800)),
                ),
              ),
            ),
          if (routineCorner != null && wide) ...[
            Positioned(top: 96, left: 0, child: _edgeHandle(i18n, theme, routineCorner.$1)),
            if (_edgeOpen) Positioned.fill(child: _edgePanel(i18n, theme, routineCorner)),
          ],
          if (_paywallOpen) Positioned.fill(child: _paywall(i18n, theme, user != null, subscribeHref)),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg, Color border) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Text(text, style: tx(10, w: 6, c: fg)),
      );

  Widget _header(I18n i18n, RebiTheme theme, bool hasConversation) {
    final u = _usage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Tw.surface.withValues(alpha: .7),
        border: Border(bottom: BorderSide(color: theme.cardBorder)),
      ),
      child: Row(
        children: [
          GradientIconBox(icon: LucideIcons.bot, from: theme.accent, to: theme.primary, size: 40, iconSize: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Rebi', style: tx(14, w: 7)),
                    if (u?.kind == 'free_daily' && u?.limit != null && u?.remaining != null)
                      _badge(i18n.t('chat.usageBadgeDay', {'rem': u!.remaining, 'lim': u.limit}), Tw.gray100, Tw.gray700,
                          Tw.gray200.withValues(alpha: .8)),
                    if (u?.kind == 'plus_monthly' && u?.limit != null && u?.remaining != null)
                      _badge(i18n.t('chat.usageBadgeMonth', {'rem': u!.remaining, 'lim': u.limit}), Tw.violet50, Tw.violet900,
                          Tw.violet200.withValues(alpha: .8)),
                    if (u?.kind == 'plus_unlimited')
                      _badge(i18n.t('chat.usageBadgeUnlimited'), Tw.emerald50, Tw.emerald900, Tw.emerald200.withValues(alpha: .8)),
                  ],
                ),
                Text(i18n.t('chat.subtitle'), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(11, c: Tw.gray500)),
              ],
            ),
          ),
          Opacity(
            opacity: hasConversation ? 1 : .4,
            child: TextButton(
              onPressed: hasConversation ? _clearChat : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(i18n.t('chat.clear'), style: tx(10, c: Tw.gray400)),
            ),
          ),
        ],
      ),
    );
  }

  List<ChatSuggestion> _currentSuggestions(I18n i18n) => chatSuggestions(_plan, DateTime.now(), i18n);

  Widget _suggestionChip(RebiTheme theme, ChatSuggestion s) {
    return Semantics(
      button: true,
      label: s.text,
      child: Material(
        color: theme.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _send(s.text),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300, minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.primary.withValues(alpha: .3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.sparkles, size: 14, color: theme.primary),
                const SizedBox(width: 8),
                Flexible(child: Text(s.text, style: tx(13, w: 5, c: theme.primaryDark, h: snug))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Konuşma sürerken giriş alanının üstünde yatay kayan öneriler.
  Widget _suggestionStrip(I18n i18n, RebiTheme theme) {
    if (_loading || _paywallOpen || _input.text.isNotEmpty) return const SizedBox.shrink();
    final items = _currentSuggestions(i18n);
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _suggestionChip(theme, items[i]),
      ),
    );
  }

  Widget _empty(I18n i18n, RebiTheme theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * .4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: .95,
              child: GradientIconBox(icon: LucideIcons.sparkles, from: theme.accent, to: theme.primary, size: 56, iconSize: 28),
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Text(i18n.t('chat.emptyTitle'), textAlign: TextAlign.center, style: tx(24, w: 6, h: snug, ls: -.4)),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Text(i18n.t('chat.emptySubtitle'), textAlign: TextAlign.center, style: tx(16, c: Tw.gray600, h: relaxed)),
            ),
            const SizedBox(height: 24),
            Text(i18n.t('mobileChat.suggestionsTitle'), style: tx(12, w: 7, c: Tw.gray600)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [for (final s in _currentSuggestions(i18n)) _suggestionChip(theme, s)],
              ),
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 384),
              child: Text(i18n.t('chat.dataHint'), textAlign: TextAlign.center, style: tx(12, c: Tw.gray500, h: relaxed)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messages(RebiTheme theme) {
    final count = _history.length + (_loading ? 1 : 0);
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i >= _history.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Tw.gray100,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(6),
                ),
              ),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: theme.primary)),
            ),
          );
        }
        final m = _history[i];
        final mine = m['role'] == 'user';
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: .85,
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: mine ? theme.primary : Tw.gray100,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 6),
                    bottomRight: Radius.circular(mine ? 6 : 16),
                  ),
                ),
                child: SelectableText(m['content'] ?? '', style: tx(14, c: mine ? Colors.white : Tw.gray800, h: relaxed)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _inputBar(I18n i18n, RebiTheme theme, String subscribeHref) {
    final u = _usage;
    final canSend = !_loading && !_paywallOpen && _input.text.trim().isNotEmpty;
    Widget footer;
    if (u?.kind == 'free_daily') {
      footer = Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (plusPurchasable) ...[
            GestureDetector(
              onTap: () => context.go(subscribeHref),
              child: Text(i18n.t('chat.plusUpgradeLink'), style: tx(10, w: 6, c: theme.primary)),
            ),
            Text(' · ', style: tx(10, c: Tw.gray500)),
          ],
          Text(i18n.t('chat.footerHintShort'), style: tx(10, c: Tw.gray400)),
        ],
      );
    } else if (u?.kind == 'plus_monthly') {
      footer = Text(i18n.t('chat.plusPack1000Footer'), textAlign: TextAlign.center, style: tx(10, c: Tw.violet800.withValues(alpha: .9)));
    } else if (u?.kind == 'plus_unlimited') {
      footer = Text(i18n.t('chat.plusUnlimitedFooter'),
          textAlign: TextAlign.center, style: tx(10, w: 5, c: Tw.emerald800.withValues(alpha: .85)));
    } else {
      footer = Text.rich(
        TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(LucideIcons.sparkles, size: 12, color: Tw.gray400),
          ),
          TextSpan(text: ' ${i18n.t('chat.footerHint')}'),
        ]),
        textAlign: TextAlign.center,
        style: tx(10, c: Tw.gray400),
      );
    }

    // Büyük yazı boyutunda dipnotlar ekranı kaplamasın: çubuk ekranın %42'siyle sınırlı, taşarsa kayar.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .42),
      child: SingleChildScrollView(child: _inputBarBody(i18n, theme, canSend, footer)),
    );
  }

  Widget _inputBarBody(I18n i18n, RebiTheme theme, bool canSend, Widget footer) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Tw.surface.withValues(alpha: .9),
        border: Border(top: BorderSide(color: theme.cardBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  // Web yanıt beklerken girişi kilitler ve sonra yeniden odaklar; mobilde salt-okunur
                  // tutmak aynı kilidi sağlar ve klavyenin kapanıp açılmasını önler.
                  readOnly: _loading || _paywallOpen,
                  textInputAction: TextInputAction.send,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => _send(),
                  style: tx(14),
                  decoration: inputDecoration(hint: i18n.t('chat.placeholder'))
                      .copyWith(hintStyle: tx(14, c: Tw.gray400), hintMaxLines: 1),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: canSend ? theme.primary : Tw.gray300,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: canSend ? _send : null,
                  child: const SizedBox(width: 48, height: 48, child: Icon(LucideIcons.send, size: 20, color: Colors.white)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          footer,
          const AiDisclaimer(textAlign: TextAlign.center, padding: EdgeInsets.only(top: 6)),
        ],
      ),
    );
  }

  Widget _edgeHandle(I18n i18n, RebiTheme theme, String subtitle) {
    return Material(
      color: Tw.surface.withValues(alpha: .85),
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
      child: InkWell(
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
        onTap: () => setState(() => _edgeOpen = true),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
            border: Border.all(color: Tw.gray200.withValues(alpha: .8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GradientIconBox(icon: LucideIcons.bot, from: theme.accent, to: theme.primary, size: 36, iconSize: 16, radius: 12),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i18n.t('chat.edgeTitle'), style: tx(11, w: 8)),
                  Text(subtitle, style: tx(10, c: Tw.gray500)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _edgeBox({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Tw.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Tw.gray200),
        ),
        child: child,
      );

  Widget _edgeButton(Widget child, VoidCallback onTap) => Material(
        color: Tw.gray50,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.gray200)),
            child: child,
          ),
        ),
      );

  Widget _edgePanel(I18n i18n, RebiTheme theme, (String, String, String, String) corner) {
    final recent = _history
        .where((m) => m['role'] == 'user' && (m['content'] ?? '').trim().isNotEmpty)
        .toList()
        .reversed
        .take(3)
        .toList();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _edgeOpen = false),
            child: ColoredBox(color: Tw.fixedSlate950.withValues(alpha: .25)),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: 340,
          child: Material(
            color: Tw.surface.withValues(alpha: .95),
            elevation: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.gray200))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i18n.t('chat.edgeTitle'), style: tx(12, w: 9)),
                            Text(i18n.t('chat.edgeSubtitle'),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(11, c: Tw.gray500)),
                          ],
                        ),
                      ),
                      Material(
                        color: Tw.gray100,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => _edgeOpen = false),
                          child: SizedBox(width: 36, height: 36, child: Icon(LucideIcons.x, size: 16, color: Tw.gray700)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _edgeBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(corner.$1, style: tx(11, w: 8)),
                            const SizedBox(height: 4),
                            Text(corner.$2, style: tx(11, c: Tw.gray600, h: snug)),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() => _edgeOpen = false);
                                context.go(corner.$3);
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(corner.$4, style: tx(11, w: 7, c: theme.primary)),
                                  const SizedBox(width: 6),
                                  Icon(LucideIcons.arrowRight, size: 12, color: theme.primary),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (recent.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _edgeBox(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(i18n.t('chat.edgeRecentTitle'), style: tx(11, w: 8)),
                              const SizedBox(height: 8),
                              for (final m in recent) ...[
                                _edgeButton(
                                  Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: i18n.t('chat.edgeRecentPick'), style: tx(11, w: 7, c: Tw.gray800)),
                                      TextSpan(
                                        text: ' ${_short(m['content'] ?? '')}',
                                        style: tx(11, c: Tw.gray600),
                                      ),
                                    ]),
                                  ),
                                  () {
                                    setState(() => _edgeOpen = false);
                                    _input.text = m['content'] ?? '';
                                    Future.delayed(const Duration(milliseconds: 50), () => _focus.requestFocus());
                                  },
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _edgeBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i18n.t('chat.edgeQuickTitle'), style: tx(11, w: 8)),
                            const SizedBox(height: 8),
                            _edgeButton(Text(i18n.t('chat.edgeQuickDashboard'), style: tx(11, w: 7, c: Tw.gray800)), () {
                              setState(() => _edgeOpen = false);
                              context.go('/dashboard');
                            }),
                            const SizedBox(height: 8),
                            _edgeButton(Text(i18n.t('chat.edgeQuickAnalyze'), style: tx(11, w: 7, c: Tw.gray800)), () {
                              setState(() => _edgeOpen = false);
                              context.go('/dashboard/analyze');
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _short(String s) {
    final t = s.trim();
    return t.length > 64 ? '${t.substring(0, 64)}…' : t;
  }

  Widget _paywall(I18n i18n, RebiTheme theme, bool loggedIn, String subscribeHref) {
    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: Tw.amber300.withValues(alpha: .9), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: tx(12, c: Colors.white.withValues(alpha: .7)))),
            ],
          ),
        );

    Widget lightButton(Widget leading, String label, VoidCallback onTap) => Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          elevation: 6,
          shadowColor: Colors.black26,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: 8),
                  Flexible(child: Text(label, style: tx(16, w: 8, c: Tw.fixedViolet950))),
                  const SizedBox(width: 8),
                  Icon(LucideIcons.arrowRight, size: 16, color: Tw.fixedViolet950),
                ],
              ),
            ),
          ),
        );

    Widget ghostButton(List<Widget> children, VoidCallback onTap) => Material(
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: .15)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: children),
            ),
          ),
        );

    final month = _paywallKind == 'plus_monthly';
    // Satın alma yolu yoksa panel yalnızca "limit doldu" bilgisini verir; Plus tanıtımı ve düğmeleri çıkmaz.
    final offer = plusPurchasable;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _paywallOpen = false),
            child: ColoredBox(color: Tw.fixedSlate950.withValues(alpha: .7)),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: .1)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Tw.fixedSlate950, Tw.fixedViolet950.withValues(alpha: .95), Tw.fixedSlate950],
                  ),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 50, offset: Offset(0, 25))],
                ),
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: Opacity(
                        opacity: .55,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(-.64, -.5),
                              radius: .9,
                              colors: [Color(0x73A78BFA), Color(0x00A78BFA)],
                              stops: [0, .42],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: Opacity(
                        opacity: .55,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(.64, .4),
                              radius: .9,
                              colors: [Color(0x47F472B6), Color(0x00F472B6)],
                              stops: [0, .38],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GradientIconBox(
                                  icon: offer ? LucideIcons.crown : LucideIcons.messageCircle, from: theme.accent, to: theme.primary, size: 48, iconSize: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(offer ? 'REBI PLUS' : i18n.t('mobileChat.limit.label'),
                                        style: tx(12, w: 7, c: Tw.amber200.withValues(alpha: .9))),
                                    const SizedBox(height: 4),
                                    Text(
                                        offer
                                            ? (month ? i18n.t('chat.paywallTitleMonth') : i18n.t('chat.paywallTitleDay'))
                                            : i18n.t(month ? 'mobileChat.limit.titleMonth' : 'mobileChat.limit.titleDay'),
                                        style: tx(24, w: 9, c: Colors.white, h: tight)),
                                    const SizedBox(height: 8),
                                    Text(
                                        offer
                                            ? (month ? i18n.t('chat.paywallBodyMonth') : i18n.t('chat.paywallBodyDay'))
                                            : i18n.t(month ? 'mobileChat.limit.bodyMonth' : 'mobileChat.limit.bodyDay'),
                                        style: tx(14, c: Tw.violet100.withValues(alpha: .85), h: relaxed)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Material(
                                color: Colors.white.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => setState(() => _paywallOpen = false),
                                  child: SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Icon(LucideIcons.x, size: 16, color: Colors.white.withValues(alpha: .8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (!loggedIn) ...[
                            lightButton(Icon(LucideIcons.lock, size: 16, color: Tw.fixedViolet950), 'Giriş yap',
                                () => context.go('/auth?next=${Uri.encodeComponent('/dashboard/chat')}')),
                            const SizedBox(height: 12),
                            if (offer)
                              ghostButton([
                                Icon(LucideIcons.crown, size: 16, color: Tw.amber300),
                                const SizedBox(width: 8),
                                Flexible(child: Text('Plus’a geç', style: tx(16, w: 7, c: Colors.white))),
                                const SizedBox(width: 8),
                                const Icon(LucideIcons.arrowRight, size: 16, color: Colors.white),
                              ], () => context.go(subscribeHref))
                            else
                              ghostButton([Flexible(child: Text(i18n.t('mobileChat.limit.close'), style: tx(16, w: 7, c: Colors.white)))],
                                  () => setState(() => _paywallOpen = false)),
                            const SizedBox(height: 4),
                            Text('Not: Rutin tarafına geçmek istersen zaten kayıt/giriş gerekiyor.',
                                textAlign: TextAlign.center, style: tx(11, c: Colors.white.withValues(alpha: .6))),
                          ] else ...[
                            if (offer) ...[
                              lightButton(Icon(LucideIcons.crown, size: 16, color: Tw.amber600), 'Rebi Plus’ı aç',
                                  () => context.go('/dashboard/subscribe')),
                              const SizedBox(height: 12),
                            ],
                            ghostButton(
                                [Flexible(child: Text(offer ? 'Şimdilik kapat' : i18n.t('mobileChat.limit.close'), style: tx(16, w: 7, c: Colors.white)))],
                                () => setState(() => _paywallOpen = false)),
                          ],
                          if (offer) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: .1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Plus ile', style: tx(12, w: 7, c: Colors.white.withValues(alpha: .9))),
                                  const SizedBox(height: 8),
                                  bullet(i18n.t('chat.paywallBulletUnlimited')),
                                  bullet('Takip + check-in verisiyle daha tutarlı öneriler'),
                                  bullet('Premium temalar ve yeni özellikler'),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
