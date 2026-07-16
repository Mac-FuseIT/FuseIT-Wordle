import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SolitaireService {
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>?> getToday() async {
    final res = await http.get(
      Uri.parse('/api/solitaire/today'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  static Future<Map<String, dynamic>?> move(
    Map<String, dynamic> from,
    Map<String, dynamic> to,
  ) async {
    final res = await http.post(
      Uri.parse('/api/solitaire/move'),
      headers: await _headers(),
      body: jsonEncode({'from': from, 'to': to}),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  static Future<Map<String, dynamic>?> draw() async {
    final res = await http.post(
      Uri.parse('/api/solitaire/draw'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  static Future<Map<String, dynamic>?> recycle() async {
    final res = await http.post(
      Uri.parse('/api/solitaire/recycle'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  static Future<Map<String, dynamic>?> giveUp() async {
    final res = await http.post(
      Uri.parse('/api/solitaire/give-up'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  static Future<Map<String, dynamic>?> getLeaderboard() async {
    final res = await http.get(
      Uri.parse('/api/solitaire/leaderboard'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }
}
