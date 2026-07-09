import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_theme.dart';
import 'blackjack_mp_screen.dart';
import 'blackjack_screen.dart';

class BlackjackLobbyScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final String nickname;
  final int userId;

  const BlackjackLobbyScreen({
    super.key,
    required this.theme,
    required this.onBack,
    required this.nickname,
    required this.userId,
  });

  @override
  State<BlackjackLobbyScreen> createState() => _BlackjackLobbyScreenState();
}

class _BlackjackLobbyScreenState extends State<BlackjackLobbyScreen> {
  bool _loading = true;
  bool _playing = false;
  int _lbTab = 0; // 0 = daily, 1 = monthly

  // Today's session state
  int? _balance;
  int? _finalBalance;
  bool _cashedOut = false;
  int _handsPlayed = 0;
  int _handsWon = 0;

  // Leaderboard data
  List<Map<String, dynamic>> _daily = [];
  List<Map<String, dynamic>> _monthly = [];

  // Multiplayer state
  List<Map<String, dynamic>> _mpGames = [];
  bool _mpLoading = false;
  String? _mpGameId; // when non-null, show multiplayer screen
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadGames());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final headers = await _getHeaders();
      final results = await Future.wait([
        http.get(Uri.parse('/api/blackjack/today'), headers: headers),
        http.get(Uri.parse('/api/blackjack/leaderboard'), headers: headers),
      ]);

      final todayRes = results[0];
      final lbRes = results[1];

      if (todayRes.statusCode == 200) {
        final data = jsonDecode(todayRes.body);
        setState(() {
          _balance = data['balance'];
          _cashedOut = data['cashedOut'] ?? false;
          _finalBalance = _cashedOut ? data['balance'] : null;
          _handsPlayed = data['handsPlayed'] ?? 0;
          _handsWon = data['handsWon'] ?? 0;
        });
      }

      if (lbRes.statusCode == 200) {
        final data = jsonDecode(lbRes.body);
        setState(() {
          _daily = List<Map<String, dynamic>>.from(data['daily'] ?? []);
          _monthly = List<Map<String, dynamic>>.from(data['monthly'] ?? []);
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
    await _loadGames();
  }

  Future<void> _loadGames() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('/api/blackjack-mp/games'), headers: headers);
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _mpGames = List<Map<String, dynamic>>.from(data['games'] ?? []);
        });
      }
    } catch (_) {}
  }

  Future<void> _createMpGame() async {
    setState(() => _mpLoading = true);
    try {
      final headers = await _getHeaders();
      final res = await http.post(Uri.parse('/api/blackjack-mp/create'), headers: headers);
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _mpGameId = data['gameId']);
      }
    } catch (_) {}
    if (mounted) setState(() => _mpLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_mpGameId != null) {
      return BlackjackMpScreen(
        theme: widget.theme,
        onBack: () => setState(() {
          _mpGameId = null;
          _load();
        }),
        nickname: widget.nickname,
        userId: widget.userId,
        gameId: _mpGameId!,
      );
    }

    if (_playing) {
      return BlackjackScreen(
        theme: widget.theme,
        onBack: () => setState(() {
          _playing = false;
          _load();
        }),
        nickname: widget.nickname,
        userId: widget.userId,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: widget.onBack,
              ),
              const Text(
                'Stack.IT',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatusCard(),
                          const SizedBox(height: 24),
                          _buildPlayButton(),
                          const SizedBox(height: 12),
                          _buildPlayWithFriendsButton(),
                          if (_mpGames.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildOpenTables(),
                          ],
                          const SizedBox(height: 32),
                          const Divider(color: Color(0xFF3A3A3C)),
                          const SizedBox(height: 16),
                          _buildLeaderboardTabs(),
                          const SizedBox(height: 12),
                          _buildLeaderboard(),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    if (_cashedOut && _finalBalance != null) {
      final profit = _finalBalance! - 100;
      final profitColor = profit >= 0 ? widget.theme.correct : Colors.red;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3A3A3C)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: widget.theme.correct, size: 18),
                const SizedBox(width: 8),
                Text("Today's Session — Cashed Out", style: TextStyle(color: widget.theme.correct, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Final: \$${_finalBalance!}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                Text(
                  '${profit >= 0 ? '+' : ''}\$$profit',
                  style: TextStyle(color: profitColor, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('$_handsPlayed hands played, $_handsWon won', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    if (_balance != null) {
      final busted = _balance! <= 0;
      final profit = _balance! - 100;
      final profitColor = profit >= 0 ? widget.theme.correct : Colors.red;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3A3A3C)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(busted ? Icons.money_off : Icons.casino, color: busted ? Colors.red : widget.theme.present, size: 18),
                const SizedBox(width: 8),
                Text(
                  busted ? "Today's Session — Busted!" : "Today's Session — In Progress",
                  style: TextStyle(color: busted ? Colors.red : widget.theme.present, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Balance: \$$_balance', style: const TextStyle(color: Colors.white, fontSize: 16)),
                Text(
                  '${profit >= 0 ? '+' : ''}\$$profit',
                  style: TextStyle(color: profitColor, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('$_handsPlayed hands played, $_handsWon won', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: const Row(
        children: [
          Icon(Icons.casino, color: Colors.grey, size: 18),
          SizedBox(width: 8),
          Text('No session today — Start with \$100', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPlayButton() {
    final busted = _balance != null && _balance! <= 0 && !_cashedOut;
    final canPlay = !_cashedOut && !busted;
    final label = _cashedOut
        ? 'Already Cashed Out Today'
        : busted
            ? 'Busted! No Balance Left'
            : (_balance != null ? 'Continue Playing' : 'Play — Start with \$100');

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: canPlay ? () => setState(() => _playing = true) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canPlay ? widget.theme.correct : const Color(0xFF3A3A3C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: canPlay ? Colors.white : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayWithFriendsButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _mpLoading ? null : _createMpGame,
        icon: const Icon(Icons.people, color: Colors.white),
        label: Text(
          _mpLoading ? 'Creating...' : 'Play with Friends',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.theme.present,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildOpenTables() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Open Tables',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._mpGames.map((game) {
          final creatorName = game['creator_name'] ?? 'Unknown';
          final playerCount = game['player_count'] ?? 1;
          final maxPlayers = game['max_players'] ?? 4;
          final status = game['status'] ?? 'waiting';
          final isFull = playerCount >= maxPlayers;
          final gameId = game['id'] as String;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A3A3C)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$creatorName's table",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$playerCount/$maxPlayers players • $status',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (!isFull)
                  ElevatedButton(
                    onPressed: () => setState(() => _mpGameId = gameId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.theme.correct,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('Join', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLeaderboardTabs() {
    return Row(
      children: [
        _buildTab('Daily', 0),
        const SizedBox(width: 8),
        _buildTab('Monthly', 1),
      ],
    );
  }

  Widget _buildTab(String label, int index) {
    final selected = _lbTab == index;
    return GestureDetector(
      onTap: () => setState(() => _lbTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? widget.theme.correct.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? widget.theme.correct : const Color(0xFF3A3A3C)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? widget.theme.correct : Colors.grey,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboard() {
    final data = _lbTab == 0 ? _daily : _monthly;
    final isMonthly = _lbTab == 1;

    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('No results yet. Be the first!', style: TextStyle(color: Colors.grey, fontSize: 14)),
      );
    }

    return Column(
      children: data.asMap().entries.map((entry) {
        final i = entry.key;
        final row = entry.value;
        final profit = isMonthly ? (row['total_profit'] ?? 0) as num : (row['profit'] ?? 0) as num;
        final profitColor = profit >= 0 ? widget.theme.correct : Colors.red;
        final nickname = row['nickname'] ?? row['name'] ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3C)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '#${i + 1}',
                  style: TextStyle(
                    color: i == 0 ? widget.theme.correct : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(nickname.toString(), style: const TextStyle(color: Colors.white)),
              ),
              Text(
                '${profit >= 0 ? '+' : ''}\$$profit',
                style: TextStyle(color: profitColor, fontWeight: FontWeight.bold),
              ),
              if (!isMonthly) ...[
                const SizedBox(width: 12),
                Text(
                  '${row['hands_played'] ?? 0} hands',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
              if (isMonthly) ...[
                const SizedBox(width: 12),
                Text(
                  '${row['games'] ?? ''} days',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
