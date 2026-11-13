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
          // Sunucunun güncel su düğmeleri (backend/today_plan.py REMINDER_ACTIONS): "İçtim" / "İçmedim".
          jsonEncode([
            {'id': 'waterYes', 'label': 'İçtim'},
            {'id': 'waterNo', 'label': 'İçmedim'},
          ]),
    };

void main() {
  test('yalnızca-veri hatırlatıcısı yerel bildirimle aynı düğme ve yükle okunur', () {
    final r = PushReminder.fromData(_water())!;

    expect((r.title, r.body, r.reminderId), ('Su içme zamanı', 'Günlük hedef 2000 ml.', 'water_intake'));
    expect([for (final a in r.actions) a.id], ['water_intake:waterYes', 'water_intake:waterNo']);
    expect([for (final a in r.actions) a.label], ['İçtim', 'İçmedim']);
    final payload = NotificationPayload.decode(r.payload.encode())!;
    expect((payload.route, payload.reminderId, payload.userId, payload.day),
        ('/dashboard', 'water_intake', 'u1', '2026-10-28'));
  });

  test('düğmeye dokunuş uygulamanın kendi eylemine çözülür', () {
    final r = PushReminder.fromData(_water())!;
    final drank = resolveNotificationAction(r.reminderId, r.actions.first.id);
    expect(drank?.type, 'water_intake');
    expect(drank?.payload, {'ml': 250});

    final skipped = resolveNotificationAction(r.reminderId, r.actions.last.id);
    expect(skipped?.type, 'water_skipped');
  });

  test('sunucunun bilmediği ya da uygulamanın tanımadığı düğme eklenmez', () {
    final r = PushReminder.fromData(_water(actions: jsonEncode([
      {'id': 'waterNo', 'label': 'İçmedim'},
      {'id': 'water9999', 'label': 'Kova'},
    ])))!;

    expect([for (final a in r.actions) a.id], ['water_intake:waterNo']);
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
