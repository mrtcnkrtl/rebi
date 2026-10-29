import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/chat_context.dart';
import '../core/chat_failure.dart';
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
import '../ui/brand/palette.dart';
import 'chat/chat_composer.dart';
import 'chat/chat_limit_card.dart';
import 'chat/chat_parts.dart';

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
  const ChatScreen({super.key, this.initialPrompt});

  /// Açılışta kendiliğinden gönderilecek mesaj (ör. Rafım'dan "yerine ne kullanabilirim?"); boşsa yok sayılır.
  final String? initialPrompt;

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

  /// Bugünün planı; öneri çipleri ve "Rebi bugünü biliyor" şeridi buradan çıkar. Plan yoksa genel sorular gösterilir.
  TodayPlan? _plan;

  /// Son mesajın yanıtı alınamadıysa nedeni (hata kartı + "Tekrar dene"); mesaj geçmişte kalır, hata kalmaz.
  ChatFailure? _failure;
  int? _failureStatus;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _effectiveUserId = _auth.user?.id ?? demoUserId;
    _history = loadChatHistory(_effectiveUserId);
    _historyOwnerId = _effectiveUserId;
    _auth.addListener(_onAuthChanged);
    _loadForUser();
    final prompt = widget.initialPrompt?.trim() ?? '';
    if (prompt.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send(prompt);
      });
    }
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
      _failure = null;
      _failureStatus = null;
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
    setState(() {
      _failure = null;
      _failureStatus = null;
    });
    _setHistory([..._history, {'role': 'user', 'content': msg}]);
    await _deliver();
  }

  /// Hata kartındaki "Tekrar dene": son kullanıcı mesajı zaten geçmişte; yeniden gönderilir.
  Future<void> _retry() async {
    if (_loading || _history.isEmpty || _history.last['role'] != 'user') return;
    setState(() {
      _failure = null;
      _failureStatus = null;
    });
    await _deliver();
  }

  void _fail(ChatFailure failure, [int? status]) => setState(() {
        _failure = failure;
        _failureStatus = status;
      });

  /// Geçmişin son mesajını (kullanıcınınki) sunucuya gönderir; yanıt geçmişe eklenir, hata geçmişe girmez.
  Future<void> _deliver() async {
    final newHist = List<ChatMessage>.of(_history);
    final msg = newHist.last['content'] ?? '';
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
        _fail(ChatFailure.fromStatus(res.status), res.status);
        _scrollToEnd();
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
      _fail(isNetworkError(e) ? ChatFailure.offline : ChatFailure.generic);
      _scrollToEnd();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearChat() async {
    _setHistory([]);
    setState(() {
      _paywallOpen = false;
      _failure = null;
      _failureStatus = null;
    });
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
    // Köşe sayacı ve rutin kenar düğmesi sohbet sütununun (672) iki yanındaki boşluğa yerleşir; boşluk yoksa
    // (iPhone Duo dış ekranı yatay, küçük tablet) mesajların üstüne binmesinler diye gösterilmez.
    final wide = MediaQuery.of(context).size.width >= 920;

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
    String? usageLabel;
    if (u?.kind == 'free_daily' && u?.remaining != null && u?.limit != null) {
      usageLabel = i18n.t('chat.usageBadgeDay', {'rem': u!.remaining, 'lim': u.limit});
    } else if (u?.kind == 'plus_monthly' && u?.remaining != null && u?.limit != null) {
      usageLabel = i18n.t('chat.usageBadgeMonth', {'rem': u!.remaining, 'lim': u.limit});
    } else if (u?.kind == 'plus_unlimited') {
      usageLabel = i18n.t('chat.usageBadgeUnlimited');
    }

    final canSend = !_loading && !_paywallOpen && _input.text.trim().isNotEmpty;
    return ThemedBackground(
      theme: theme,
      child: Stack(
        children: [
          CenteredBox(
            maxWidth: 672,
            child: Column(
              children: [
                ChatHeader(theme: theme, usageLabel: usageLabel, canClear: hasConversation, onClear: _clearChat),
                ChatContextStrip(
                  items: chatContext(_plan, i18n),
                  theme: theme,
                  onTap: () => context.go('/dashboard'),
                ),
                Expanded(child: hasConversation ? _messages(i18n, theme) : _empty(i18n, theme)),
                if (_paywallOpen)
                  _limitCard(theme, user != null, subscribeHref)
                else if (hasConversation)
                  _suggestionStrip(i18n, theme),
                ChatComposer(
                  theme: theme,
                  controller: _input,
                  focusNode: _focus,
                  locked: _loading || _paywallOpen,
                  canSend: canSend,
                  onSend: _send,
                  footer: _footer(i18n, theme),
                  compact: _paywallOpen,
                ),
              ],
            ),
          ),
          // Geniş ekranda (tablet) köşe sayacı ve rutin kenar çekmecesi.
          if (usageLabel != null && wide)
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
                  ),
                  child: Text(usageLabel, style: tx(11, w: 6, c: Tw.gray800)),
                ),
              ),
            ),
          if (routineCorner != null && wide) ...[
            Positioned(top: 140, left: 0, child: _edgeHandle(i18n, theme, routineCorner.$1)),
            if (_edgeOpen) Positioned.fill(child: _edgePanel(i18n, theme, routineCorner)),
          ],
        ],
      ),
    );
  }

  /// Giriş alanının altındaki kota notu (pakete göre).
  Widget _footer(I18n i18n, RebiTheme theme) {
    final u = _usage;
    if (u?.kind == 'free_daily') {
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (plusPurchasable) ...[
            GestureDetector(
              onTap: () => context.go(_auth.user != null ? '/dashboard/subscribe' : '/auth?next=${Uri.encodeComponent('/dashboard/subscribe')}'),
              child: Text(i18n.t('chat.plusUpgradeLink'), style: tx(11, w: 6, c: theme.fg)),
            ),
            Text(' · ', style: tx(11, c: Tw.gray500)),
          ],
          Text(i18n.t('chat.footerHintShort'), style: tx(11, c: Tw.gray500)),
        ],
      );
    }
    if (u?.kind == 'plus_monthly') {
      return Text(i18n.t('chat.plusPack1000Footer'), textAlign: TextAlign.center, style: tx(11, c: Tw.gray500));
    }
    if (u?.kind == 'plus_unlimited') {
      return Text(i18n.t('chat.plusUnlimitedFooter'), textAlign: TextAlign.center, style: tx(11, w: 5, c: Tw.gray500));
    }
    return Text.rich(
      TextSpan(children: [
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(LucideIcons.sparkles, size: 12, color: Tw.gray400)),
        TextSpan(text: ' ${i18n.t('chat.footerHint')}'),
      ]),
      textAlign: TextAlign.center,
      style: tx(11, c: Tw.gray500),
    );
  }

  /// Sohbet hakkı doldu kartı; sohbetin altında, kısa ekranda kayar.
  Widget _limitCard(RebiTheme theme, bool loggedIn, String subscribeHref) {
    return Flexible(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: ChatLimitCard(
          theme: theme,
          month: _paywallKind == 'plus_monthly',
          offer: plusPurchasable,
          loggedIn: loggedIn,
          onClose: () => setState(() => _paywallOpen = false),
          onSignIn: () => context.go('/auth?next=${Uri.encodeComponent('/dashboard/chat')}'),
          onPlus: () => context.go(loggedIn ? '/dashboard/subscribe' : subscribeHref),
        ),
      ),
    );
  }

  List<ChatSuggestion> _currentSuggestions(I18n i18n) => chatSuggestions(_plan, DateTime.now(), i18n);

  /// Konuşma sürerken giriş alanının üstünde yatay kayan öneri çipi.
  Widget _suggestionChip(RebiTheme theme, ChatSuggestion s) {
    return Semantics(
      button: true,
      label: s.text,
      child: Material(
        color: Tw.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.primary.withValues(alpha: .28))),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _send(s.text),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260, minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.sparkles, size: 14, color: theme.fg),
                const SizedBox(width: 8),
                Flexible(child: Text(s.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(13, w: 5, c: Tw.gray800, h: snug))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Boş sohbette: tam genişlikte, dokunması kolay soru satırı.
  Widget _suggestionRow(RebiTheme theme, ChatSuggestion s) {
    return Semantics(
      button: true,
      label: s.text,
      child: Material(
        color: Tw.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Tw.gray100)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _send(s.text),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: theme.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(LucideIcons.sparkles, size: 15, color: theme.fg),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(s.text, style: tx(14, w: 5, c: Tw.gray800, h: snug))),
                const SizedBox(width: 8),
                Icon(LucideIcons.arrowUpRight, size: 16, color: Tw.gray400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _suggestionStrip(I18n i18n, RebiTheme theme) {
    if (_loading || _paywallOpen || _input.text.isNotEmpty || _failure != null) return const SizedBox.shrink();
    final items = _currentSuggestions(i18n);
    return SizedBox(
      height: 72,
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
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(i18n.t('chat.emptyTitle'), textAlign: TextAlign.center, style: heading(28, h: 1.2)),
              const SizedBox(height: 10),
              Text(i18n.t('chat.emptySubtitle'), textAlign: TextAlign.center, style: tx(15, c: Tw.gray600, h: relaxed)),
              const SizedBox(height: 26),
              Text(i18n.t('mobileChat.suggestionsTitle'), style: tx(11, w: 7, c: Tw.gray500, ls: 1.2)),
              const SizedBox(height: 10),
              for (final s in _currentSuggestions(i18n)) ...[
                _suggestionRow(theme, s),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 14),
              Text(i18n.t('chat.dataHint'), textAlign: TextAlign.center, style: tx(12, c: Tw.gray500, h: relaxed)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messages(I18n i18n, RebiTheme theme) {
    final failure = _failure;
    final extras = (_loading ? 1 : 0) + (failure != null ? 1 : 0);
    final count = _history.length + extras;
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i >= _history.length) {
          if (_loading) return TypingBubble(theme: theme);
          return ChatErrorCard(failure: failure!, theme: theme, status: _failureStatus, onRetry: _retry);
        }
        final m = _history[i];
        return ChatBubble(text: m['content'] ?? '', mine: m['role'] == 'user', theme: theme);
      },
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
                                  Text(corner.$4, style: tx(11, w: 7, c: theme.fg)),
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
}
