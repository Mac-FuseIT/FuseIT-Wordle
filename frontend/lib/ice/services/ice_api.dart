import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class IceApi {
  static const String baseUrl = '';

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken');
  }

  static Future<List<Map<String, dynamic>>> getSessions() async {
    final res = await http.get(Uri.parse('$baseUrl/api/ice/sessions'));
    if (res.statusCode != 200) throw Exception('Failed to load sessions');
    final data = jsonDecode(res.body);
    return List<Map<String, dynamic>>.from(data['sessions']);
  }

  static Future<String> createSession(int bestOf, double puckSpeed, int playersPerSide) async {
    final token = await _getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/api/ice/create'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'bestOf': bestOf, 'puckSpeed': puckSpeed, 'playersPerSide': playersPerSide}),
    );
    if (res.statusCode != 200) throw Exception('Failed to create session');
    final data = jsonDecode(res.body);
    return data['sessionId'];
  }
}
