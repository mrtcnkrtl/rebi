/// Sohbet isteğinin neden sonuç vermediği; ekran buna göre sakin bir hata kartı ve "Tekrar dene" gösterir.
/// (Eskiden hata metni sohbetin içine "asistan mesajı" olarak yazılıyor ve sonraki isteklerde geçmiş olarak
/// sunucuya gidiyordu; artık geçmişe hiç girmez.)
enum ChatFailure {
  /// Bağlantı yok / zaman aşımı.
  offline,

  /// Sunucu geçici olarak yanıt vermiyor (502, 503).
  server,

  /// Oturum doğrulanamadı (401).
  auth,

  /// Diğer.
  generic;

  /// HTTP durumundan neden.
  static ChatFailure fromStatus(int status) => switch (status) {
        401 => ChatFailure.auth,
        502 || 503 || 504 => ChatFailure.server,
        _ => ChatFailure.generic,
      };

  /// `mobileChat.error.*` çeviri anahtarı.
  String get messageKey => 'mobileChat.error.$name';
}
