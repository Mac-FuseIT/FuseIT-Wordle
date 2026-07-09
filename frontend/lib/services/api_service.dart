import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_state.dart';

class ApiService {
  static const String baseUrl = '';
  static String? _token;
  static void Function()? onUnauthorized;

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

  static void _checkUnauthorized(http.Response res) {
    if (res.statusCode == 401 && onUnauthorized != null) {
      clearToken();
      onUnauthorized!();
    }
  }

  static Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  static Future<http.Response> _authGet(String path) async {
    await _loadToken();
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: _authHeaders);
    _checkUnauthorized(res);
    return res;
  }

  static Future<http.Response> _authPost(String path, {Object? body}) async {
    await _loadToken();
    final res = await http.post(Uri.parse('$baseUrl$path'), headers: _authHeaders, body: body != null ? jsonEncode(body) : null);
    _checkUnauthorized(res);
    return res;
  }

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

  static Future<bool> invadeCheckpoint(String sessionToken, int score, int level) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/api/invade/checkpoint'),
      headers: _authHeaders,
      body: jsonEncode({'sessionToken': sessionToken, 'score': score, 'level': level}),
    );
    return res.statusCode == 200;
  }

  static Future<void> submitInvadeScore(int score, int level, String sessionToken) async {
    await _loadToken();
    await http.post(
      Uri.parse('$baseUrl/api/invade/score'),
      headers: _authHeaders,
      body: jsonEncode({'sessionToken': sessionToken, 'score': score, 'level': level}),
    );
  }

  // Chess.IT
  static Future<Map<String, dynamic>> getChessToday() async {
    final res = await _authGet('/api/chess/today');
    return jsonDecode(res.body);
  }

  static Future<bool> submitChessResult(bool won, int moves, int redosUsed, List<String> moveHistory, String fen) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/api/chess/submit'),
      headers: _authHeaders,
      body: jsonEncode({'won': won, 'moves': moves, 'redosUsed': redosUsed, 'moveHistory': moveHistory, 'fen': fen}),
    );
    return res.statusCode == 200;
  }

  static Future<bool> saveChessSession(String fen, List<String> moveHistory, int moveCount, int redosUsed) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/api/chess/save'),
      headers: _authHeaders,
      body: jsonEncode({'fen': fen, 'moveHistory': moveHistory, 'moveCount': moveCount, 'redosUsed': redosUsed}),
    );
    return res.statusCode == 200;
  }

  static Future<Map<String, dynamic>> getChessLeaderboard() async {
    await _loadToken();
    final res = await http.get(Uri.parse('$baseUrl/api/chess/leaderboard'), headers: _authHeaders);
    return jsonDecode(res.body);
  }

  // Phantom Chess.IT
  static Future<Map<String, dynamic>> getPhantomChessToday() async {
    await _loadToken();
    final res = await http.get(Uri.parse('$baseUrl/api/phantom-chess/today'), headers: _authHeaders);
    return jsonDecode(res.body);
  }

  static Future<bool> submitPhantomChessResult(bool won, int moves, int redosUsed, List<String> moveHistory) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/api/phantom-chess/submit'),
      headers: _authHeaders,
      body: jsonEncode({'won': won, 'moves': moves, 'redosUsed': redosUsed, 'moveHistory': moveHistory}),
    );
    return res.statusCode == 200;
  }

  static Future<bool> savePhantomChessSession(String fen, List<String> moveHistory, int moveCount, int redosUsed) async {
    await _loadToken();
    final res = await http.post(
      Uri.parse('$baseUrl/api/phantom-chess/save'),
      headers: _authHeaders,
      body: jsonEncode({'fen': fen, 'moveHistory': moveHistory, 'moveCount': moveCount, 'redosUsed': redosUsed}),
    );
    return res.statusCode == 200;
  }

  static Future<Map<String, dynamic>> getPhantomChessLeaderboard() async {
    await _loadToken();
    final res = await http.get(Uri.parse('$baseUrl/api/phantom-chess/leaderboard'), headers: _authHeaders);
    return jsonDecode(res.body);
  }

  // Chess PvP
  static Future<Map<String, dynamic>> getChessPvpLobby() async {
    await _loadToken();
    final res = await http.get(Uri.parse('$baseUrl/api/chess-pvp/lobby'), headers: _authHeaders);
    return jsonDecode(res.body);
  }

  static Future<String?> createChessPvpChallenge(int opponentId, String colorChoice, String timeControl) async {
    await _loadToken();
    final res = await http.post(Uri.parse('$baseUrl/api/chess-pvp/challenge'), headers: _authHeaders,
      body: jsonEncode({'opponentId': opponentId, 'colorChoice': colorChoice, 'timeControl': timeControl}));
    final data = jsonDecode(res.body);
    return data['challengeId'];
  }

  static Future<String?> acceptChessPvpChallenge(String challengeId) async {
    await _loadToken();
    final res = await http.post(Uri.parse('$baseUrl/api/chess-pvp/accept'), headers: _authHeaders,
      body: jsonEncode({'challengeId': challengeId}));
    final data = jsonDecode(res.body);
    return data['sessionId'];
  }

  static Future<void> declineChessPvpChallenge(String challengeId) async {
    await _loadToken();
    await http.post(Uri.parse('$baseUrl/api/chess-pvp/decline'), headers: _authHeaders,
      body: jsonEncode({'challengeId': challengeId}));
  }

  static Future<Map<String, dynamic>> getChessPvpLeaderboard() async {
    await _loadToken();
    final res = await http.get(Uri.parse('$baseUrl/api/chess-pvp/leaderboard'), headers: _authHeaders);
    return jsonDecode(res.body);
  }

  // Blackjack (Jack.IT)
  static Future<Map<String, dynamic>> getBlackjackToday() async {
    final res = await _authGet('/api/blackjack/today');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> blackjackBet(int amount) async {
    final res = await _authPost('/api/blackjack/bet', body: {'amount': amount});
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> blackjackHit() async {
    final res = await _authPost('/api/blackjack/hit');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> blackjackStand() async {
    final res = await _authPost('/api/blackjack/stand');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> blackjackDouble() async {
    final res = await _authPost('/api/blackjack/double');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> blackjackCashout() async {
    final res = await _authPost('/api/blackjack/cashout');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getBlackjackLeaderboard() async {
    final res = await _authGet('/api/blackjack/leaderboard');
    return jsonDecode(res.body);
  }

  static List<GuessResult> parseGuesses(List<dynamic> raw) {
    return raw.map((g) => GuessResult.fromJson(g as Map<String, dynamic>)).toList();
  }
}
