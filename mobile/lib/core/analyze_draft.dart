import 'local_store.dart';

/// Analiz sihirbazının yarım kalan cevapları. Kullanıcı çıkarsa, uygulama kapanırsa ya da yanlışlıkla
/// başa dönerse cevaplar kaybolmasın diye cihazda tutulur; rutin üretilince silinir.
/// Fotoğraf saklanmaz (dosya yolu geçicidir); kullanıcıya da taslakta fotoğrafın kalmadığı söylenir.
String analyzeDraftKey(String userId) => 'rebi_analyze_draft_$userId';

/// Taslak bu süreden eskiyse sorulmaz (cevaplar bayatlar, cilt değişir).
const analyzeDraftMaxAge = Duration(days: 14);

Map<String, dynamic>? getAnalyzeDraft(String? userId) {
  if (userId == null || userId.isEmpty) return null;
  final v = LocalStore.instance.getJson(analyzeDraftKey(userId));
  if (v is! Map) return null;
  final draft = v.cast<String, dynamic>();
  final savedAt = draft['savedAt'];
  if (savedAt is! num) return null;
  final age = DateTime.now().millisecondsSinceEpoch - savedAt.toInt();
  if (age < 0 || age > analyzeDraftMaxAge.inMilliseconds) return null;
  final answers = draft['answers'];
  if (answers is! Map || answers.isEmpty) return null;
  return draft;
}

Future<void> saveAnalyzeDraft(
  String? userId, {
  required String pageId,
  required bool stressTest,
  required Map<String, dynamic> answers,
}) async {
  if (userId == null || userId.isEmpty) return;
  await LocalStore.instance.setJson(analyzeDraftKey(userId), {
    'savedAt': DateTime.now().millisecondsSinceEpoch,
    'pageId': pageId,
    'stressTest': stressTest,
    'answers': answers,
  });
}

Future<void> clearAnalyzeDraft(String? userId) async {
  if (userId == null || userId.isEmpty) return;
  await LocalStore.instance.remove(analyzeDraftKey(userId));
}
