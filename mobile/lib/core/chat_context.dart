import 'i18n.dart';
import 'today_plan.dart';

/// Sohbet ekranının "Rebi bugünü biliyor" şeridindeki tek bilgi.
class ChatContextItem {
  const ChatContextItem(this.id, this.text);

  /// `weather` | `routine` | `water` | `makeup` | `shelf`: arayüzün ikon ve rengi seçmesi için.
  final String id;
  final String text;
}

/// Sohbetin bugün hakkında bildiği şeyler (sunucu da aynı özeti modele verir: `chat_context.py`). Hava yalnızca
/// gerçek bir kaynaktan geldiyse gösterilir; varsayılan hava "biliyorum" denecek bir şey değildir.
List<ChatContextItem> chatContext(TodayPlan? plan, I18n i18n) {
  if (plan == null) return const [];
  final p = plan.progress;
  final items = <ChatContextItem>[];

  if (plan.hasRealWeather) {
    final uv = _num(plan.weather['uv_index']);
    final temp = _num(plan.weather['temperature']);
    if (uv != null && temp != null) {
      items.add(ChatContextItem('weather', i18n.t('mobileChat.context.weather', {'uv': uv.round(), 'temp': temp.round()})));
    }
  }

  if (plan.hasRoutine) {
    final done = (p.morningDone ? 1 : 0) + (p.eveningDone ? 1 : 0);
    items.add(ChatContextItem(
      'routine',
      done == 2 ? i18n.t('mobileChat.context.routineDone') : i18n.t('mobileChat.context.routine', {'done': done, 'total': 2}),
    ));
  }

  items.add(ChatContextItem(
    'water',
    i18n.t('mobileChat.context.water', {'ml': p.waterMl, 'target': plan.waterTarget}),
  ));

  if (p.makeupUsed) {
    items.add(ChatContextItem(
      'makeup',
      i18n.t(p.makeupRemoved ? 'mobileChat.context.makeupDone' : 'mobileChat.context.makeupPending'),
    ));
  }

  if (plan.productsOut.isNotEmpty) {
    items.add(ChatContextItem('shelf', i18n.t('mobileChat.context.shelf', {'n': plan.productsOut.length})));
  }
  return items;
}

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
