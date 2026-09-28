import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_state.dart';

class ApiService {
  static const String baseUrl = '';
  static String? _token;
  static void Function()? onUnauthorized;

  // ─── Rate limiting ──────────────────────────────────────────────────────────
  // Prevents rapid-fire requests to the same endpoint. If a request is already
  // in-flight for a given key, subsequent calls return the in-flight future.
  // Also enforces a minimum cooldown between requests to the same endpoint.
  static final Map<String, Future<http.Response>> _inFlight = {};
  static final Map<String, DateTime> _lastRequest = {};
  static const Duration _minCooldown = Duration(milliseconds: 800);

  /// Wraps a request with deduplication and cooldown.
  /// If a request to [key] is already in-flight, returns that same future.
  /// If the last request to [key] was less than [_minCooldown] ago, returns an
  /// error response without hitting the network.
  static Future<http.Response> _throttled(String key, Future<http.Response> Function() makeRequest) async {
    // If already in-flight, return the existing future (dedup)
    if (_inFlight.containsKey(key)) {
      return _inFlight[key]!;
    }

    // If cooldown hasn't elapsed, return a synthetic throttle response
    final last = _lastRequest[key];
    if (last != null && DateTime.now().difference(last) < _minCooldown) {
      return http.Response('{"error":"Please wait before submitting again"}', 429);
    }

    // Execute the request
    final future = makeRequest().whenComplete(() {
      _inFlight.remove(key);
      _lastRequest[key] = DateTime.now();
    });
    _inFlight[key] = future;
    return future;
  }

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

  /// Public helper for independent service classes that make their own HTTP
  /// calls. Call this after every authenticated request so that a 401 response
  /// triggers the global logout flow regardless of which service issued the
  /// request.
  static void notifyIfUnauthorized(int statusCode) {
    if (statusCode == 401 && onUnauthorized != null) {
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
    final res = await _authPost('/api/profile', body: {
      if (nickname != null) 'nickname': nickname!,
      if (newPassword != null) 'newPassword': newPassword!,
      if (theme != null) 'theme': theme!,
    });
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getToday() async {
    final res = await http.get(Uri.parse('$baseUrl/api/today'));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> submitGuess(int userId, String guess) async {
    await _loadToken();
    final res = await _throttled('guess', () => http.post(
      Uri.parse('$baseUrl/api/guess'),
      headers: _authHeaders,
      body: jsonEncode({'guess': guess}),
    ));
    _checkUnauthorized(res);
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getGameState(int userId) async {
    final res = await _authGet('/api/guess');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getLeaderboard(String date, {int? userId}) async {
    final res = await _authGet('/api/leaderboard?date=$date');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getInvadeLeaderboard() async {
    final res = await _authGet('/api/invade/leaderboard');
    return jsonDecode(res.body);
  }
  static Future<String?> startInvadeSession() async {
    final res = await _authPost('/api/invade/start');
    final data = jsonDecode(res.body);
    return data['sessionToken'] as String?;
  }

  static Future<bool> invadeCheckpoint(String sessionToken, int score, int level) async {
    final res = await _authPost(
      '/api/invade/checkpoint',
      body: {'sessionToken': sessionToken, 'score': score, 'level': level},
    );
    return res.statusCode == 200;
  }

  static Future<void> submitInvadeScore(int score, int level, String sessionToken) async {
    await _authPost(
      '/api/invade/score',
      body: {'sessionToken': sessionToken, 'score': score, 'level': level},
    );
  }

  // Chess.IT
  static Future<Map<String, dynamic>> getChessToday({String mode = 'expert'}) async {
    final res = await _authGet('/api/chess/today?mode=$mode');
    return jsonDecode(res.body);
  }

  static Future<bool> submitChessResult(bool won, int moves, int redosUsed, List<String> moveHistory, String fen, {String mode = 'expert'}) async {
    final res = await _authPost(
      '/api/chess/submit',
      body: {'won': won, 'moves': moves, 'redosUsed': redosUsed, 'moveHistory': moveHistory, 'fen': fen, 'mode': mode},
    );
    return res.statusCode == 200;
  }

  static Future<bool> saveChessSession(String fen, List<String> moveHistory, int moveCount, int redosUsed, {String mode = 'expert'}) async {
    final res = await _authPost(
      '/api/chess/save',
      body: {'fen': fen, 'moveHistory': moveHistory, 'moveCount': moveCount, 'redosUsed': redosUsed, 'mode': mode},
    );
    return res.statusCode == 200;
  }

  static Future<Map<String, dynamic>> getChessLeaderboard({String mode = 'expert'}) async {
    final res = await _authGet('/api/chess/leaderboard?mode=$mode');
    return jsonDecode(res.body);
  }

  // Phantom Chess.IT
  static Future<Map<String, dynamic>> getPhantomChessToday() async {
    final res = await _authGet('/api/phantom-chess/today');
    return jsonDecode(res.body);
  }

  static Future<bool> submitPhantomChessResult(bool won, int moves, int redosUsed, List<String> moveHistory) async {
    final res = await _authPost(
      '/api/phantom-chess/submit',
      body: {'won': won, 'moves': moves, 'redosUsed': redosUsed, 'moveHistory': moveHistory},
    );
    return res.statusCode == 200;
  }

  static Future<bool> savePhantomChessSession(String fen, List<String> moveHistory, int moveCount, int redosUsed) async {
    final res = await _authPost(
      '/api/phantom-chess/save',
      body: {'fen': fen, 'moveHistory': moveHistory, 'moveCount': moveCount, 'redosUsed': redosUsed},
    );
    return res.statusCode == 200;
  }

  static Future<Map<String, dynamic>> getPhantomChessLeaderboard() async {
    final res = await _authGet('/api/phantom-chess/leaderboard');
    return jsonDecode(res.body);
  }

  // Chess PvP
  static Future<Map<String, dynamic>> getChessPvpLobby() async {
    final res = await _authGet('/api/chess-pvp/lobby');
    return jsonDecode(res.body);
  }

  static Future<String?> createChessPvpChallenge(int opponentId, String colorChoice, String timeControl) async {
    final res = await _authPost('/api/chess-pvp/challenge',
      body: {'opponentId': opponentId, 'colorChoice': colorChoice, 'timeControl': timeControl});
    final data = jsonDecode(res.body);
    return data['challengeId'];
  }

  static Future<String?> acceptChessPvpChallenge(String challengeId) async {
    final res = await _authPost('/api/chess-pvp/accept',
      body: {'challengeId': challengeId});
    final data = jsonDecode(res.body);
    return data['sessionId'];
  }

  static Future<void> declineChessPvpChallenge(String challengeId) async {
    await _authPost('/api/chess-pvp/decline',
      body: {'challengeId': challengeId});
  }

  static Future<Map<String, dynamic>> getChessPvpLeaderboard() async {
    final res = await _authGet('/api/chess-pvp/leaderboard');
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

  // Chain.IT
  static Future<Map<String, dynamic>> getChainItToday() async {
    final res = await _authGet('/api/chainit/today');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> submitChainItGuess(String guess) async {
    final res = await _throttled('chainit_guess', () => _authPost('/api/chainit/guess', body: {'guess': guess}));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getChainItLeaderboard() async {
    final res = await _authGet('/api/chainit/leaderboard');
    return jsonDecode(res.body);
  }
}
