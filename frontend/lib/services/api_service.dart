import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_state.dart';

class ApiService {
  static const String baseUrl = '';
  static String? _token;

  static Future<void> _loadToken() async {
    if (_token != null) return;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('authToken');
  }

  static Future<void> _saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('authToken', token);
  }

  static Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
  }

  static Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  static Future<Map<String, dynamic>> register(String email) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (data['token'] != null) {
      await _saveToken(data['token']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> updateProfile(int userId, {String? nickname, String? newPassword, Map<String, dynamic>? theme}) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/api/profile'),
      headers: _authHeaders,
      body: jsonEncode({
        if (nickname != null) 'nickname': nickname,
        if (newPassword != null) 'newPassword': newPassword,
        if (theme != null) 'theme': theme,
      }),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getToday() async {
    final res = await http.get(Uri.parse('$baseUrl/api/today'));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> submitGuess(int userId, String guess) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/api/guess'),
      headers: _authHeaders,
      body: jsonEncode({'guess': guess}),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getGameState(int userId) async {
    await _loadToken();
    final res = await http.get(
      Uri.parse('$baseUrl/api/guess'),
      headers: _authHeaders,
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getLeaderboard(String date, {int? userId}) async {
    await _loadToken();
    final res = await http.get(
      Uri.parse('$baseUrl/api/leaderboard?date=$date'),
      headers: _authHeaders,
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getInvadeLeaderboard() async {
    await _loadToken();
    final res = await http.get(Uri.parse('$baseUrl/api/invade/leaderboard'), headers: _authHeaders);
    return jsonDecode(res.body);
  }
  static Future<String?> startInvadeSession() async {
    await _loadToken();
    final res = await http.post(Uri.parse('$baseUrl/api/invade/start'), headers: _authHeaders);
    final data = jsonDecode(res.body);
    return data['sessionToken'] as String?;
  }

  static Future<void> submitInvadeScore(int score, int level, String sessionToken) async {
    await _loadToken();
    await http.post(
      Uri.parse('$baseUrl/api/invade/score'),
      headers: _authHeaders,
      body: jsonEncode({'score': score, 'level': level, 'sessionToken': sessionToken}),
    );
  }

  static List<GuessResult> parseGuesses(List<dynamic> raw) {
    return raw.map((g) => GuessResult.fromJson(g as Map<String, dynamic>)).toList();
  }
}
