import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Supabase yapılandırılmamışsa null (web: `supabase` null).
SupabaseClient? get supabase => Env.supabaseConfigured ? Supabase.instance.client : null;

String get apiUrl => Env.apiUrl;

/// FastAPI yanıtı: durum kodu + gövde (JSON değilse boş map, webdeki `res.json().catch(() => ({}))`).
class ApiResponse {
  const ApiResponse(this.status, this.data);

  final int status;
  final Map<String, dynamic> data;

  bool get ok => status >= 200 && status < 300;
}

/// FastAPI çağrılarında kullanılan Authorization başlığı (web: `lib/apiAuth.js`).
/// Oturumun süresi dolmuşsa önce yeniler; JS SDK `getSession()` bunu kendiliğinden yapar.
Future<Map<String, String>> apiAuthHeaders() async {
  final client = supabase;
  if (client == null) return {};
  var session = client.auth.currentSession;
  if (session == null || session.isExpired) {
    try {
      session = (await client.auth.refreshSession()).session ?? session;
    } catch (_) {
      /* yenilenemedi: aşağıda mevcut anahtarla devam (sunucu 401 döner) */
    }
  }
  final token = session?.accessToken;
  if (token == null || token.isEmpty) return {};
  return {'Authorization': 'Bearer $token'};
}

/// Cihazın UTC farkı (dakika). Sunucu "bugün"ü kullanıcının yerel gününe göre hesaplasın diye
/// gün içi uçlara gönderilir; yoksa gece 00:00-03:00 (TR) arası bir önceki gün görünür.
String localUtcOffsetMinutes([DateTime? now]) => '${(now ?? DateTime.now()).timeZoneOffset.inMinutes}';

/// Okuma, olay kaydı ve ayar uçları: bağlantı kötüyse ekran iki dakika dönmesin, kısa sürede bırakılır
/// (olay kaydı çevrimdışı kuyrukta bekler, ekranlar yerel kopyayla açılır).
const apiTimeout = Duration(seconds: 20);

/// Yapay zekâ ya da toplu işlem yapan uçlar (rutin üretme, sohbet, check-in notu, çeviri, hesap silme).
const apiLongTimeout = Duration(seconds: 120);

http.Client _http = http.Client();

/// Testlerde sahte istemci (ör. `MockClient`) takmak için.
@visibleForTesting
set apiHttpClient(http.Client client) => _http = client;

Uri apiUri(String path, [Map<String, String?>? query]) {
  final q = <String, String>{};
  query?.forEach((k, v) {
    if (v != null) q[k] = v;
  });
  final base = Uri.parse('$apiUrl$path');
  return q.isEmpty ? base : base.replace(queryParameters: {...base.queryParameters, ...q});
}

Map<String, dynamic> _decode(http.Response res) {
  try {
    final body = utf8.decode(res.bodyBytes);
    final v = jsonDecode(body);
    return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

Future<ApiResponse> apiGet(String path, {Map<String, String?>? query, bool auth = true, Duration timeout = apiTimeout}) async {
  final headers = auth ? await apiAuthHeaders() : <String, String>{};
  final res = await _http.get(apiUri(path, query), headers: headers).timeout(timeout);
  return ApiResponse(res.statusCode, _decode(res));
}

Future<ApiResponse> apiPost(String path, Object? body, {bool auth = true, Duration timeout = apiTimeout}) async {
  final headers = {
    'Content-Type': 'application/json',
    if (auth) ...await apiAuthHeaders(),
  };
  final res = await _http.post(apiUri(path), headers: headers, body: jsonEncode(body)).timeout(timeout);
  return ApiResponse(res.statusCode, _decode(res));
}

Future<ApiResponse> apiPatch(String path, Object? body, {Duration timeout = apiTimeout}) async {
  final headers = {'Content-Type': 'application/json', ...await apiAuthHeaders()};
  final res = await _http.patch(apiUri(path), headers: headers, body: jsonEncode(body)).timeout(timeout);
  return ApiResponse(res.statusCode, _decode(res));
}

Future<ApiResponse> apiPut(String path, Object? body, {Duration timeout = apiTimeout}) async {
  final headers = {'Content-Type': 'application/json', ...await apiAuthHeaders()};
  final res = await _http.put(apiUri(path), headers: headers, body: jsonEncode(body)).timeout(timeout);
  return ApiResponse(res.statusCode, _decode(res));
}

Future<ApiResponse> apiDelete(String path, {Map<String, String?>? query, Duration timeout = apiTimeout}) async {
  final headers = await apiAuthHeaders();
  final res = await _http.delete(apiUri(path, query), headers: headers).timeout(timeout);
  return ApiResponse(res.statusCode, _decode(res));
}

/// FastAPI / Starlette hata gövdesi: { detail: string | { msg }[] | ... } (web: `lib/apiErrors.js`).
String formatApiErrorDetail(Map<String, dynamic>? data) {
  if (data == null) return 'Sunucudan anlamlı bir yanıt alınamadı.';
  final d = data['detail'];
  if (d is String) return d;
  if (d is List) {
    return d
        .map((e) {
          if (e is String) return e;
          if (e is Map) return (e['msg'] ?? e['message'] ?? jsonEncode(e)).toString();
          return e.toString();
        })
        .where((s) => s.isNotEmpty)
        .join(' ');
  }
  if (d is Map && d['msg'] is String) return d['msg'] as String;
  if (data['message'] is String) return data['message'] as String;
  return 'İşlem tamamlanamadı. Bir süre sonra tekrar dene.';
}

/// Web `isNetworkError`: "Failed to fetch" karşılığı bağlantı hataları.
bool isNetworkError(Object err) =>
    err is SocketException ||
    err is http.ClientException ||
    err is TimeoutException ||
    err is HandshakeException ||
    err is HttpException;

/// `data?.detail || fallback` — hata mesajını istisna olarak fırlatmak için.
String detailOr(Map<String, dynamic> data, String fallback) {
  final d = data['detail'];
  if (d == null) return fallback;
  if (d is String) return d.isEmpty ? fallback : d;
  return formatApiErrorDetail(data);
}
