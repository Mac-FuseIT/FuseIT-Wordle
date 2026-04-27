import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CrosswordApi {
  static const String baseUrl = '';

  static Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Future<Map<String, dynamic>> getToday() async {
    final res = await http.get(Uri.parse('$baseUrl/api/crossword/today'), headers: await _headers);
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getAnswer() async {
    final res = await http.get(Uri.parse('$baseUrl/api/crossword/answer'), headers: await _headers);
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> save(List<List<String?>> grid, int elapsed, {int hintsUsed = 0, int checksUsed = 0}) async {
    final res = await http.post(Uri.parse('$baseUrl/api/crossword/save'), headers: await _headers, body: jsonEncode({'grid': grid, 'elapsed': elapsed, 'hintsUsed': hintsUsed, 'checksUsed': checksUsed}));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> complete(List<List<String?>> grid, int elapsed) async {
    final res = await http.post(Uri.parse('$baseUrl/api/crossword/complete'), headers: await _headers, body: jsonEncode({'grid': grid, 'elapsed': elapsed}));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> giveUp(int elapsed) async {
    final res = await http.post(Uri.parse('$baseUrl/api/crossword/giveup'), headers: await _headers, body: jsonEncode({'elapsed': elapsed}));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getLeaderboard() async {
    final res = await http.get(Uri.parse('$baseUrl/api/crossword/leaderboard'), headers: await _headers);
    return jsonDecode(res.body);
  }
}
