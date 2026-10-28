import 'api.dart';

/// `GET /me/profile` yanıtı: sunucudaki `profiles` kaydı. Analiz sihirbazı da bu kaydı yazar;
/// cilt tipi, bugünün havaya göre önerilerini ve sohbetin kişiselleştirmesini etkiler.
class UserProfile {
  const UserProfile({this.fullName, this.skinType, this.age, this.gender, this.city, this.updatedAt, this.synced = true});

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        fullName: _text(j['full_name']),
        skinType: _text(j['skin_type']),
        age: j['age'] is num ? (j['age'] as num).toInt() : int.tryParse('${j['age'] ?? ''}'),
        gender: _text(j['gender']),
        city: _text(j['city']),
        updatedAt: _text(j['updated_at']),
        synced: j['synced'] != false,
      );

  final String? fullName;
  final String? skinType;
  final int? age;
  final String? gender;
  final String? city;
  final String? updatedAt;

  /// false: kullanıcı verisi sunucuda tutulmuyor (demo / veritabanı yok); değişiklikler kaydedilmez.
  final bool synced;

  /// Sunucunun kabul ettiği değerler (`SkinTypeName`, `gender` Literal'ları).
  static const skinTypes = ['normal', 'dry', 'oily', 'combination', 'sensitive'];
  static const genders = ['female', 'male', 'other'];

  /// Sunucu yaşı bu aralığa sabitler; istemci sessizce değiştirmek yerine baştan uyarır.
  static const minAge = 13;
  static const maxAge = 100;
}

String? _text(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Yaş alanı geçerli mi. Boş geçerlidir (değişiklik yok). Dönüş: hata varsa true.
bool isInvalidAge(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  final n = int.tryParse(t);
  return n == null || n < UserProfile.minAge || n > UserProfile.maxAge;
}

/// `PATCH /me/profile` gövdesi: yalnızca verilen alanlar değişir.
class ProfileUpdate {
  const ProfileUpdate({this.fullName, this.skinType, this.age, this.gender, this.city});

  final String? fullName;
  final String? skinType;
  final int? age;
  final String? gender;

  /// Boş metin şehri temizler (sunucu `null`ı "dokunma" sayar, boş metni yazar).
  final String? city;

  bool get isEmpty => fullName == null && skinType == null && age == null && gender == null && city == null;

  Map<String, dynamic> toBody(String userId) => {
        'user_id': userId,
        if (fullName != null) 'full_name': fullName,
        if (skinType != null) 'skin_type': skinType,
        if (age != null) 'age': age,
        if (gender != null) 'gender': gender,
        if (city != null) 'city': city,
      };
}

class ProfileSaveResult {
  const ProfileSaveResult({this.profile, this.error, this.networkError = false});

  final UserProfile? profile;
  final String? error;
  final bool networkError;

  bool get ok => profile != null;
}

/// Başarısızlıkta (ağ yok, 401, 5xx) null döner.
Future<UserProfile?> fetchMyProfile(String userId) async {
  final res = await apiGet('/me/profile', query: {'user_id': userId});
  return res.ok ? UserProfile.fromJson(res.data) : null;
}

Future<ProfileSaveResult> updateMyProfile(String userId, ProfileUpdate update) async {
  if (update.isEmpty) return const ProfileSaveResult(error: 'Güncellenecek alan yok.');
  try {
    final res = await apiPatch('/me/profile', update.toBody(userId));
    if (!res.ok) return ProfileSaveResult(error: detailOr(res.data, 'Profil kaydedilemedi.'));
    return ProfileSaveResult(profile: UserProfile.fromJson(res.data));
  } catch (e) {
    return ProfileSaveResult(error: 'Profil kaydedilemedi.', networkError: isNetworkError(e));
  }
}
