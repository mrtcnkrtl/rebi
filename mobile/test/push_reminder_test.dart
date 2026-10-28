import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/notification_actions.dart';
import 'package:rebi/core/push_reminder.dart';

/// Sunucunun `/push/dispatch` ile gönderdiği yalnızca-veri mesajı (`docs/MOBIL-API.md` → "Bildirim verisi").
Map<String, dynamic> _water({Object? actions}) => {
      'reminder_id': 'water_intake',
      'log_event': 'water_intake',
      'log_date': '2026-10-28',
      'slot': '13:00',
      'user_id': 'u1',
      'open_path': '/dashboard',
      'title': 'Su içme zamanı',
      'body': 'Günlük hedef 2000 ml.',
      'actions': actions ??
          jsonEncode([
            {'id': 'water250', 'label': '+250 ml'},
            {'id': 'water500', 'label': '+500 ml'},
          ]),
    };

void main() {
  test('yalnızca-veri hatırlatıcısı yerel bildirimle aynı düğme ve yükle okunur', () {
    final r = PushReminder.fromData(_water())!;

    expect((r.title, r.body, r.reminderId), ('Su içme zamanı', 'Günlük hedef 2000 ml.', 'water_intake'));
    expect([for (final a in r.actions) a.id], ['water_intake:water250', 'water_intake:water500']);
    expect([for (final a in r.actions) a.label], ['+250 ml', '+500 ml']);
    final payload = NotificationPayload.decode(r.payload.encode())!;
    expect((payload.route, payload.reminderId, payload.userId, payload.day),
        ('/dashboard', 'water_intake', 'u1', '2026-10-28'));
  });

  test('düğmeye dokunuş uygulamanın kendi eylemine çözülür', () {
    final r = PushReminder.fromData(_water())!;
    final action = resolveNotificationAction(r.reminderId, r.actions.last.id);

    expect(action?.type, 'water_intake');
    expect(action?.payload, {'ml': 500});
  });

  test('sunucunun bilmediği ya da uygulamanın tanımadığı düğme eklenmez', () {
    final r = PushReminder.fromData(_water(actions: jsonEncode([
      {'id': 'water500', 'label': '+500 ml'},
      {'id': 'water9999', 'label': 'Kova'},
    ])))!;

    expect([for (final a in r.actions) a.id], ['water_intake:water500']);
  });

  test('bozuk düğme listesiyle bildirim düğmesiz gösterilir', () {
    expect(PushReminder.fromData(_water(actions: '{bozuk'))!.actions, isEmpty);
    expect(PushReminder.fromData(_water(actions: ''))!.actions, isEmpty);
  });

  test('ekran yolu yoksa hatırlatıcının ekranı açılır', () {
    final data = {
      ..._water(),
      'reminder_id': 'restock_check',
      'open_path': '',
      'actions': '[]',
    };

    expect(PushReminder.fromData(data)!.payload.route, '/dashboard/shelf');
  });

  test('başlığı veride olmayan (sistemin gösterdiği) mesaj okunmaz', () {
    expect(PushReminder.fromData({..._water()}..remove('title')), isNull);
    expect(PushReminder.fromData({..._water()}..remove('reminder_id')), isNull);
  });

  test('bildirim kimliği kararlıdır ve yerel hatırlatıcılarla çakışmaz', () {
    final a = pushNotificationId('water_intake', '2026-10-28', '13:00');

    expect(pushNotificationId('water_intake', '2026-10-28', '13:00'), a);
    expect(pushNotificationId('water_intake', '2026-10-28', '15:00'), isNot(a));
    expect(a, greaterThanOrEqualTo(100000));
  });
}
