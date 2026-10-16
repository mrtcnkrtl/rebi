import 'i18n.dart';
import 'today_plan.dart';

/// Hatırlatıcının görünen başlığı. Türkçede sunucu metni; İngilizcede, çevirisi olan
/// hatırlatıcılar çevrilir, olmayanlar sunucu metniyle gösterilir.
String reminderTitle(I18n i18n, Reminder r) =>
    i18n.prefersLocalized ? i18n.t('mobileToday.reminders.${r.id}.title', const {}, r.title) : r.title;

String reminderBody(I18n i18n, Reminder r, Map<String, dynamic> weather, {int? waterTarget}) {
  if (!i18n.prefersLocalized) return r.body;
  return i18n.t('mobileToday.reminders.${r.id}.body', _bodyVars(weather, waterTarget), r.body);
}

/// Sunucudan metni gelmeyen (yarın için kurulan) hatırlatıcıların başlığı / gövdesi:
/// her iki dilde de yerel çeviri dosyasından okunur.
String localReminderTitle(I18n i18n, String id) => i18n.t('mobileToday.reminders.$id.title', const {}, id);

String localReminderBody(I18n i18n, String id, {int? waterTarget}) =>
    i18n.t('mobileToday.reminders.$id.body', _bodyVars(const {}, waterTarget), '');

Map<String, Object?> _bodyVars(Map<String, dynamic> weather, int? waterTarget) {
  final uv = weather['uv_index'];
  return {'target': waterTarget ?? waterTargetMl, 'uv': uv is num ? uv.round() : uv ?? ''};
}
