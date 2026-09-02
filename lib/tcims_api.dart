import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ===========================================================================
// TCIMS backend client.
//
// This app and the CCAT website now share ONE MySQL database, reached
// through the same PHP API (my-app-backend/api/*.php). Firebase Auth stays
// as the identity layer (who you are); this file bridges that identity to
// the backend's own `api_token` (a bearer token), which every backend
// request after sign-in must carry.
//
// Flow: sign in with Firebase as before -> exchangeFirebaseToken() sends the
// Firebase ID token to api/firebase_login.php -> the backend verifies it,
// finds-or-creates the matching `users` row, and returns an api_token ->
// that token is cached in SharedPreferences and attached to every request
// below as `Authorization: Bearer <token>`.
// ===========================================================================
class TcimsApi {
  TcimsApi._();

  /// Live backend (Render + TiDB Cloud). For the Android emulator during
  /// local development against XAMPP instead, use
  /// 'http://10.0.2.2/my-app-backend'.
  static const String baseUrl =
      'https://tourism-cultural-information-management-kof5.onrender.com/my-app-backend';

  static const String _tokenKey = 'tcims_api_token';

  static String? _cachedToken;

  /// The current session token, if any (cached in memory after first read).
  static Future<String?> get token async {
    if (_cachedToken != null) return _cachedToken;
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
    return _cachedToken;
  }

  static Future<void> _setToken(String token) async {
    _cachedToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// Clears the cached session (e.g. after a 401, or on sign-out).
  static Future<void> clearToken() async {
    _cachedToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static bool get isSignedIn => _cachedToken != null;

  // -------------------------------------------------------------------------
  // Cold starts
  // -------------------------------------------------------------------------

  /// Nudges the backend awake without waiting for it.
  ///
  /// The free Render tier suspends the service after a period of inactivity,
  /// and the first request afterwards has to wait for the container to boot —
  /// long enough that a real submission can time out and look like a failure.
  /// Calling this at launch means the boot happens while the person is still
  /// finding their way around, so by the time they send feedback or verify a
  /// church the service is already up.
  ///
  /// Deliberately fire-and-forget and unauthenticated: the reply does not
  /// matter (a 401 wakes the container just as well as a 200), and nothing in
  /// the app should ever be held up waiting for it.
  static void warmUp() {
    http
        .get(Uri.parse('$baseUrl/api/visits.php'))
        .timeout(const Duration(seconds: 60))
        .then((_) {}, onError: (_) {});
  }

  // -------------------------------------------------------------------------
  // Auth bridge
  // -------------------------------------------------------------------------

  /// Exchanges the current Firebase sign-in for a TCIMS api_token. Call this
  /// right after every successful Firebase sign-in (email/password, Google,
  /// phone). Safe to call repeatedly — each call just re-issues a token.
  ///
  /// Returns true on success. Returns false (never throws) on any failure —
  /// callers should treat that as "backend features are unavailable this
  /// session" rather than blocking the sign-in itself; Firebase is still the
  /// source of truth for whether the person is logged in.
  static Future<bool> exchangeFirebaseToken({String role = 'Tourist'}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final idToken = await user.getIdToken(true); // force refresh
      if (idToken == null) return false;

      final res = await http
          .post(
            Uri.parse('$baseUrl/api/firebase_login.php'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': idToken, 'role': role}),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final apiToken = data['user']?['api_token'] as String?;
      if (apiToken == null || apiToken.isEmpty) return false;
      await _setToken(apiToken);
      return true;
    } catch (_) {
      // Offline, backend down, or (for phone sign-ins) no email on the
      // Firebase account — firebase_login.php requires one. The app still
      // works locally; only cross-device sync/backend features are skipped
      // for this session.
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Generic authorized requests
  // -------------------------------------------------------------------------

  static Future<Map<String, String>> _authHeaders() async {
    final t = await token;
    return {
      'Content-Type': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  /// GET with the bearer token attached. Returns the decoded JSON body, or
  /// null on any failure (no token, offline, non-200, bad JSON). A 401
  /// clears the stored token so the next check treats the session as signed
  /// out of the backend (Firebase sign-in itself is untouched).
  static Future<dynamic> get(String path) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl$path'), headers: await _authHeaders())
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 401) {
        await clearToken();
        return null;
      }
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body);
    } catch (_) {
      return null;
    }
  }

  /// POST a JSON body with the bearer token attached. Returns the decoded
  /// JSON body on 200, or null on any failure.
  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: await _authHeaders(),
            body: jsonEncode(body),
          )
          // Generous enough to survive a container that is still finishing
          // its boot when the person submits.
          .timeout(const Duration(seconds: 35));
      if (res.statusCode == 401) {
        await clearToken();
        return null;
      }
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body);
    } catch (_) {
      return null;
    }
  }

  /// Multipart POST (for the photo check-in endpoint). [fields] are plain
  /// text fields; [files] maps a form field name (e.g. 'selfie') to a local
  /// file path. Returns the decoded JSON body on 200, or null on failure.
  static Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required Map<String, String> files,
  }) async {
    try {
      final t = await token;
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
      if (t != null) req.headers['Authorization'] = 'Bearer $t';
      req.fields.addAll(fields);
      for (final entry in files.entries) {
        req.files.add(await http.MultipartFile.fromPath(entry.key, entry.value));
      }
      // Two photos over mobile data, possibly against a waking container.
      final streamed = await req.send().timeout(const Duration(seconds: 50));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 401) {
        await clearToken();
        return null;
      }
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body);
    } catch (_) {
      return null;
    }
  }
}
