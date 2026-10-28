import 'day_log.dart';
import 'i18n.dart';
import 'today_plan.dart';

/// Sohbet ekranında tek dokunuşla sorulabilen öneri.
class ChatSuggestion {
  const ChatSuggestion(this.id, this.text);

  /// `mobileChat.suggestions.*` anahtarı.
  final String id;
  final String text;
}

/// Sohbette gösterilecek en çok öneri sayısı.
const maxChatSuggestions = 4;

/// Plan yokken ya da az öneri çıkınca tamamlanan genel sorular.
const _genericIds = ['generic1', 'generic2', 'generic3'];

/// Bugünün verisinden (hava, makyaj, beslenme, su) çıkan sorular, önem sırasına göre. Veri yoksa
/// ya da hava tahmini varsayılan değerse (konum yok) havaya dair soru önerilmez: yanlış UV'yi
/// kullanıcıya söylemeyelim. En az üç öneri olacak şekilde genel sorularla tamamlanır.
List<ChatSuggestion> chatSuggestions(TodayPlan? plan, DateTime now, I18n i18n) {
  final found = <ChatSuggestion>[];

  void add(String id, [Map<String, Object?> vars = const {}]) {
    if (found.length >= maxChatSuggestions) return;
    found.add(ChatSuggestion(id, i18n.t('mobileChat.suggestions.$id', vars)));
  }

  if (plan != null) {
    final p = plan.progress;

    if (plan.hasRealWeather) {
      final uv = _num(plan.weather['uv_index']);
      final temp = _num(plan.weather['temperature']);
      final humidity = _num(plan.weather['humidity']);
      if (uv != null && uv >= 6) {
        add('uvHigh', {'uv': uv.round()});
      } else if (uv != null && uv >= 3) {
        add('uvMid', {'uv': uv.round()});
      }
      if (temp != null && temp <= 10) {
        add('cold', {'temp': temp.round()});
      } else if (temp != null && temp >= 30) {
        add('hot', {'temp': temp.round()});
      }
      if (humidity != null && humidity < 35) add('dry', {'humidity': humidity.round()});
    }

    if (p.makeupUsed && !p.makeupRemoved) {
      add('makeupPending');
    } else if (p.makeupUsed && (p.removalMethod == 'wipe' || p.removalMethod == 'water')) {
      add('makeupLight');
    }

    final food = nutritionSelection(p.nutrition);
    if (food.contains('sweets')) {
      add('sweets');
    } else if (food.contains('dairy')) {
      add('dairy');
    } else if (food.contains('snacks') || food.contains('fried_food')) {
      add('snacks');
    }

    // Akşama doğru hedefin çok gerisindeyse.
    if (now.hour >= 15 && p.waterMl < plan.waterTarget * .4) add('lowWater');
  }

  for (final id in _genericIds) {
    if (found.length >= 3) break;
    add(id);
  }
  return found;
}

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
