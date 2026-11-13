/// Supabase Auth hatalarının kullanıcıya gösterilecek türleri.
/// Hata kodu (`AuthException.code`) varsa ona, yoksa eski sürümlerin İngilizce mesajına bakılır.
enum AuthErrorKind {
  invalidCredentials,
  emailNotConfirmed,
  alreadyRegistered,
  weakPassword,
  samePassword,
  rateLimited,
  emailSendFailed,
  linkInvalid,

  /// E-postadaki 6 haneli kod yanlış ya da süresi dolmuş (Supabase bunu bağlantı hatasıyla aynı `otp_expired` koduyla
  /// bildirir; ayrımı kod giriş ekranı yapar, [classifyAuthError] üretmez).
  codeInvalid,
  network,
  notConfigured,
  other,
}

AuthErrorKind classifyAuthError(String message, {String? code, bool network = false}) {
  if (network) return AuthErrorKind.network;
  final c = (code ?? '').toLowerCase();
  final m = message.toLowerCase();
  switch (c) {
    case 'invalid_credentials':
      return AuthErrorKind.invalidCredentials;
    case 'email_not_confirmed':
      return AuthErrorKind.emailNotConfirmed;
    case 'user_already_exists':
    case 'email_exists':
      return AuthErrorKind.alreadyRegistered;
    case 'weak_password':
      return AuthErrorKind.weakPassword;
    case 'same_password':
      return AuthErrorKind.samePassword;
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
    case 'over_sms_send_rate_limit':
      return AuthErrorKind.rateLimited;
    case 'otp_expired':
    case 'flow_state_expired':
    case 'flow_state_not_found':
    case 'bad_code_verifier':
      return AuthErrorKind.linkInvalid;
    case 'unexpected_failure':
      // Çoğunlukla SMTP/e-posta sağlayıcısı hatasıdır (kayıt/sıfırlama e-postası gönderilemedi).
      if (m.contains('email') || m.contains('mail') || m.contains('smtp')) return AuthErrorKind.emailSendFailed;
  }
  if (m.contains('invalid login credentials')) return AuthErrorKind.invalidCredentials;
  if (m.contains('email not confirmed')) return AuthErrorKind.emailNotConfirmed;
  if (m.contains('already registered') || m.contains('already been registered')) return AuthErrorKind.alreadyRegistered;
  if (m.contains('same as the old') || m.contains('different from the old')) return AuthErrorKind.samePassword;
  if (m.contains('password should') || m.contains('weak password')) return AuthErrorKind.weakPassword;
  if (m.contains('error sending') && m.contains('email')) return AuthErrorKind.emailSendFailed;
  if (m.contains('rate limit') || m.contains('too many') || m.contains('exceeded') || m.contains('quota') || m.contains('429')) {
    return AuthErrorKind.rateLimited;
  }
  if (m.contains('invalid or has expired') || (m.contains('expired') && m.contains('link'))) return AuthErrorKind.linkInvalid;
  return AuthErrorKind.other;
}
