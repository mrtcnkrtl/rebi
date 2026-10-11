final _placeholder = RegExp(r'\{\{(\w+)\}\}');

/// Basit `{{anahtar}}` yer tutucu değişimi (web: `lib/interpolate.js`).
String interpolate(String? str, Map<String, Object?> vars) {
  if (str == null || str.isEmpty) return '';
  return str.replaceAllMapped(_placeholder, (m) {
    final v = vars[m.group(1)];
    return v == null ? '' : _fmt(v);
  });
}

/// JS `String(2.0)` → "2"; Dart `2.0.toString()` → "2.0". Web ile aynı görünsün diye.
String _fmt(Object v) {
  if (v is double && v == v.truncateToDouble() && v.isFinite) return v.toInt().toString();
  return v.toString();
}
