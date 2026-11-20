import 'api.dart';
import 'routine_logic.dart';

/// Kullanıcının kendi rutin düzenlemeleri (sunucu: `backend/routine_edits.py`).
///
/// Rebi'nin ürettiği adımların metni istemciden değiştirilemez. Kullanıcı iki şey yapar:
/// yapmayacağı adımı **plandan çıkarır** (silinmez, geri alınabilir) ve **kendi adımını ekler**
/// (`source: "user"`; Rebi'nin önerisi gibi gösterilmez).

/// Kullanıcı en çok bu kadar kendi adımını ekleyebilir (sunucu da aynı sayıda keser).
const maxUserSteps = 10;
const maxUserStepActionChars = 90;
const maxUserStepDetailChars = 240;

/// Kullanıcının kendi adımına verilebilecek zamanlar (sunucu `_USER_TIMES`).
const userStepTimes = ['Sabah', 'Akşam', 'Günlük'];

/// Bir adımın kalıcı kimliği — sunucudaki `step_key` ile aynı kural.
String routineStepKey(RoutineItem item) {
  final order = item['step_order'];
  return '${str(item['time']).trim()}|${order == null ? '' : str(order)}|${str(item['action']).trim()}';
}

bool isUserStep(RoutineItem item) => str(item['source']) == 'user';

bool isSkippedByUser(RoutineItem item) => item['skipped_by_user'] == true;

/// (yürürlükteki adımlar, kullanıcının çıkardıkları).
({List<RoutineItem> active, List<RoutineItem> skipped}) splitUserEdits(List<RoutineItem> items) => (
      active: items.where((i) => !isSkippedByUser(i)).toList(),
      skipped: items.where(isSkippedByUser).toList(),
    );

/// Kullanıcının yazdığı adım. Rutine `source: "user"` ile girer.
class UserRoutineStep {
  const UserRoutineStep({required this.action, this.time = 'Sabah', this.detail = ''});

  factory UserRoutineStep.fromItem(RoutineItem item) => UserRoutineStep(
        action: str(item['action']),
        time: userStepTimes.contains(str(item['time'])) ? str(item['time']) : 'Sabah',
        detail: str(item['detail']),
      );

  final String action;
  final String time;
  final String detail;

  Map<String, dynamic> toJson() => {
        'action': action.trim(),
        'time': userStepTimes.contains(time) ? time : 'Sabah',
        'detail': detail.trim(),
      };
}

/// `PUT /routine/active` yanıtı.
class RoutineEditsResult {
  const RoutineEditsResult({required this.routine, required this.skipped});

  final List<RoutineItem> routine;
  final List<RoutineItem> skipped;
}

/// Düzenlemeleri sunucuya yazar. [hidden] her zaman tam listedir: listede olmayan adımın
/// işareti kalkar, yani aynı çağrı hem çıkarmayı hem geri almayı anlatır.
/// Hata metni döndürülür (null = kaydedildi).
Future<({RoutineEditsResult? result, String? error})> saveRoutineEdits(
  String userId, {
  required Iterable<String> hidden,
  required Iterable<UserRoutineStep> added,
}) async {
  final res = await apiPut('/routine/active', {
    'user_id': userId,
    'hidden': hidden.toList(),
    'added': [for (final s in added.take(maxUserSteps)) s.toJson()],
  });
  if (!res.ok) return (result: null, error: apiErrorMessage(res));
  return (
    result: RoutineEditsResult(
      routine: asRoutine(res.data['routine']),
      skipped: asRoutine(res.data['skipped_steps']),
    ),
    error: null,
  );
}

/// `GET /routine/active`: yürürlükteki rutin + kullanıcının çıkardıkları.
Future<RoutineEditsResult?> fetchRoutineWithSkipped(String userId) async {
  final res = await apiGet('/routine/active', query: {'user_id': userId});
  if (!res.ok) return null;
  return RoutineEditsResult(
    routine: asRoutine(res.data['routine']),
    skipped: asRoutine(res.data['skipped_steps']),
  );
}
