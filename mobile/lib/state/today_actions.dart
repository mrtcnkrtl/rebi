import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/day_log.dart';
import '../core/haptics.dart';
import '../core/i18n.dart';
import 'today_plan_controller.dart';

/// Ekranın altında kısa süre görünen onay mesajı; [undo] varsa "Geri al" düğmesi çıkar.
class TodayToast {
  const TodayToast(this.message, {this.undoLabel, this.undo});

  final String message;
  final String? undoLabel;
  final Future<void> Function()? undo;
}

/// "Bugün" ekranındaki kullanıcı işlemleri: kayıt gönderme, geri alınabilir onay mesajı,
/// rutin adımı işaretleme. Kayıtların hepsi [TodayPlanController.log] üzerinden gider
/// (çevrimdışıysa kuyruğa alınır).
class TodayActions extends ChangeNotifier {
  TodayActions(this.plan);

  final TodayPlanController plan;

  String? _chosenBlock;
  TodayToast? toast;
  Timer? _toastTimer;
  bool _disposed = false;

  /// Öne çıkan rutin bloğu: kullanıcı seçtiyse o, yoksa günün saatine göre.
  String blockAt(DateTime now) => _chosenBlock ?? blockForTime(now);

  void chooseBlock(String block) {
    if (_chosenBlock == block) return;
    _chosenBlock = block;
    _notify();
  }

  Future<LogOutcome> log(String type, [Map<String, dynamic> payload = const {}]) => plan.log(type, payload);

  /// Kaydı gönderir ve sonucu bildirir: kaydedildi, kuyruğa alındı ya da kaydedilemedi.
  /// [undoPayload] verilirse mesajda "Geri al" çıkar ve aynı tipte bu yükü gönderir.
  Future<LogOutcome> record(
    String type,
    Map<String, dynamic> payload, {
    String? message,
    Map<String, dynamic>? undoPayload,

    /// Geri alma farklı bir olayla yapılıyorsa (ör. "aldım" → yeniden "bitti") tipi; verilmezse aynı tip.
    String? undoType,
  }) async {
    final i18n = I18n.instance;
    final outcome = await log(type, payload);
    if (outcome == LogOutcome.failed) {
      Haptics.failure();
      showToast(i18n.t('mobileToday.toast.failed'));
      return outcome;
    }
    Haptics.success();
    showToast(
      outcome == LogOutcome.queued ? i18n.t('mobileToday.queuedHint') : (message ?? i18n.t('dashboard.quickLogged')),
      undoLabel: undoPayload == null ? null : i18n.t('mobileToday.toast.undo'),
      undo: undoPayload == null
          ? null
          : () async {
              final undone = await log(undoType ?? type, undoPayload);
              showToast(i18n.t(undone == LogOutcome.failed ? 'mobileToday.toast.failed' : 'mobileToday.toast.undone'));
            },
    );
    return outcome;
  }

  void showToast(String message, {String? undoLabel, Future<void> Function()? undo}) {
    _toastTimer?.cancel();
    toast = TodayToast(message, undoLabel: undoLabel, undo: undo);
    _toastTimer = Timer(Duration(seconds: undo == null ? 3 : 6), dismissToast);
    _notify();
  }

  void dismissToast() {
    _toastTimer?.cancel();
    if (toast == null) return;
    toast = null;
    _notify();
  }

  /// Rutin adımını işaretler ya da işareti kaldırır. Blok bitmişken bir adımın işareti kalkarsa
  /// blok yeniden açılır ve diğer adımlar tek tek işaretli kalır; son adım da işaretlenince
  /// blok kendiliğinden tamamlanır.
  Future<void> toggleStep({required String block, required int step, required List<int> allSteps}) async {
    final progress = plan.plan?.progress;
    if (progress == null) return;
    final blockDone = progress.blockDone(block);
    final done = progress.stepsOf(block);
    Haptics.selection();
    if (!(blockDone || done.contains(step))) {
      final outcome = await log('routine_step', {'done': true, 'block': block, 'step_order': step});
      if (!outcome.saved) return;
      final all = {...done, step};
      if (allSteps.isNotEmpty && allSteps.every(all.contains)) {
        await log('routine_completed_block', {block: true});
      }
      return;
    }
    if (blockDone) {
      await log('routine_completed_block', {block: false});
      for (final other in allSteps) {
        if (other != step && !done.contains(other)) {
          await log('routine_step', {'done': true, 'block': block, 'step_order': other});
        }
      }
    }
    await log('routine_step', {'done': false, 'block': block, 'step_order': step});
  }

  /// Tamamlanmış bloğu yeniden açar. Adımlar tek tek işaretli kalır (blok toptan tamamlanmışsa hiçbir iş
  /// kaybolmasın diye önce hepsi tek tek işaretlenir), böylece kullanıcı yalnızca yanlış olanı kaldırır.
  Future<void> reopenBlock({required String block, required List<int> allSteps}) async {
    final progress = plan.plan?.progress;
    if (progress == null || !progress.blockDone(block)) return;
    Haptics.selection();
    final done = progress.stepsOf(block);
    final outcome = await log('routine_completed_block', {block: false});
    if (!outcome.saved) return;
    for (final step in allSteps) {
      if (!done.contains(step)) await log('routine_step', {'done': true, 'block': block, 'step_order': step});
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _toastTimer?.cancel();
    super.dispose();
  }
}
