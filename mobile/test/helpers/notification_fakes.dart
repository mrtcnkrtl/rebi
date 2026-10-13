import 'dart:async';

import 'package:rebi/core/notification_ports.dart';
import 'package:rebi/core/reminder_schedule.dart';

/// Gerçek bildirim eklentisi yerine: kurulan bildirimleri ve çağrıları kaydeder.
class FakeReminderNotifier implements ReminderNotifier {
  FakeReminderNotifier({this.supported = true, this.permission = true});

  @override
  bool supported;

  /// İşletim sisteminin şu anki izni.
  bool permission;

  /// `requestPermission` çağrılınca sistemin vereceği cevap.
  bool grantOnRequest = true;

  String? launch;
  int permissionRequests = 0;
  int cancelCalls = 0;
  final List<List<PlannedNotification>> replaced = [];
  final StreamController<String> _taps = StreamController<String>.broadcast();

  List<PlannedNotification> get scheduled => replaced.isEmpty ? const [] : replaced.last;

  void tap(String route) => _taps.add(route);

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    if (grantOnRequest) permission = true;
    return grantOnRequest;
  }

  @override
  Future<void> replaceAll(List<PlannedNotification> items) async {
    replaced.add(items);
  }

  @override
  Future<void> cancelAll() async {
    cancelCalls++;
    replaced.add(const []);
  }

  @override
  Future<String?> launchRoute() async => launch;

  @override
  Stream<String> get taps => _taps.stream;
}

class FakePushClient implements PushClient {
  FakePushClient({this.available = true, this.pushToken = 'fcm-token-1'});

  @override
  bool available;

  String? pushToken;
  int permissionRequests = 0;
  String? initial;
  final StreamController<String> _refresh = StreamController<String>.broadcast();
  final StreamController<String> _opened = StreamController<String>.broadcast();

  void refreshToken(String next) {
    pushToken = next;
    _refresh.add(next);
  }

  void open(String route) => _opened.add(route);

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<String?> token() async => pushToken;

  @override
  Stream<String> get tokenRefreshes => _refresh.stream;

  @override
  Stream<String> get opened => _opened.stream;

  @override
  Future<String?> initialOpened() async => initial;
}
