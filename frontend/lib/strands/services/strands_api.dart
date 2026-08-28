import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class StrandsApi {
  static const String baseUrl = '';

  // ─── Rate limiting ──────────────────────────────────────────────────────────
  static Future<http.Response>? _checkInFlight;
  static DateTime? _lastCheck;
  static const Duration _minCooldown = Duration(milliseconds: 800);

  static Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Future<Map<String, dynamic>> getToday() async {
    final res = await http.get(Uri.parse('$baseUrl/api/strands/today'), headers: await _headers);
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> checkWord(List<List<int>> path) async {
    // If already in-flight, return existing future result
    if (_checkInFlight != null) {
      final res = await _checkInFlight!;
      return jsonDecode(res.body);
    }

    // Cooldown check
    if (_lastCheck != null && DateTime.now().difference(_lastCheck!) < _minCooldown) {
      return {'type': 'invalid'};
    }

    final future = http.post(Uri.parse('$baseUrl/api/strands/check'), headers: await _headers, body: jsonEncode({'path': path}));
    _checkInFlight = future;
    try {
      final res = await future;
      return jsonDecode(res.body);
    } finally {
      _checkInFlight = null;
      _lastCheck = DateTime.now();
    }
  }

  static Future<Map<String, dynamic>> useHint() async {
    final res = await http.post(Uri.parse('$baseUrl/api/strands/hint'), headers: await _headers, body: '{}');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getLeaderboard() async {
    final res = await http.get(Uri.parse('$baseUrl/api/strands/leaderboard'), headers: await _headers);
    return jsonDecode(res.body);
  }
}
