import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/game_state.dart';

class ApiService {
  // Empty string means same origin (works with Pages Functions)
  static const String baseUrl = '';

  static Future<Map<String, dynamic>> login(String name) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
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

  static Future<Map<String, dynamic>> getLeaderboard(String date) async {
    final res = await http.get(Uri.parse('$baseUrl/api/leaderboard?date=$date'));
    return jsonDecode(res.body);
  }

  static List<GuessResult> parseGuesses(List<dynamic> raw) {
    return raw.map((g) => GuessResult.fromJson(g as Map<String, dynamic>)).toList();
  }
}
