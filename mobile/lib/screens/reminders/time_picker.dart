import 'package:flutter/material.dart';

/// Saat seçici. Testlerde gerçek iletişim kutusu yerine sabit bir saat vermek için değiştirilir.
Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initial) reminderTimePicker = (context, initial) =>
    showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );

/// [reminderTimePicker] ile saat seçtirir; dönüş gün başından dakika, vazgeçilirse null.
Future<int?> pickClockMinutes(BuildContext context, int current) async {
  final picked = await reminderTimePicker(context, TimeOfDay(hour: current ~/ 60, minute: current % 60));
  return picked == null ? null : picked.hour * 60 + picked.minute;
}
