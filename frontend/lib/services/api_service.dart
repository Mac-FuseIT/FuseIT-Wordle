import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/game_state.dart';

class ApiService {
  static const String baseUrl = '';

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
    return jsonDecode(res.body);
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
    final res = await http.post(
      Uri.parse('$baseUrl/api/profile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
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
    final res = await http.post(
      Uri.parse('$baseUrl/api/guess'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'guess': guess}),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getGameState(int userId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/guess?userId=$userId'));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getLeaderboard(String date, {int? userId}) async {
    var url = '$baseUrl/api/leaderboard?date=$date';
    if (userId != null) url += '&userId=$userId';
    final res = await http.get(Uri.parse(url));
    return jsonDecode(res.body);
  }

  static List<GuessResult> parseGuesses(List<dynamic> raw) {
    return raw.map((g) => GuessResult.fromJson(g as Map<String, dynamic>)).toList();
  }
}
