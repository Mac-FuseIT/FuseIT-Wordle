import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/help_dialog.dart';
import 'chess_game_screen.dart';
import 'phantom_game_screen.dart';

class ChessLobbyScreen extends StatefulWidget {
  final String nickname;
  final int userId;
  final AppTheme theme;
  final VoidCallback onBack;

  const ChessLobbyScreen({super.key, required this.nickname, required this.userId, required this.theme, required this.onBack});

  @override
  State<ChessLobbyScreen> createState() => _ChessLobbyScreenState();
}

class _ChessLobbyScreenState extends State<ChessLobbyScreen> {
  bool _loading = true;
  bool _playing = false;
  bool _playingPhantom = false;
  bool _played = false;
  bool? _won;
  int? _moves;
  int _botLevel = 800;
  Map<String, dynamic>? _session;
  String _playerColor = 'white';
  bool _phantomPlayed = false;
  bool? _phantomWon;
  int? _phantomMoves;
  int _phantomBotLevel = 400;
  Map<String, dynamic>? _phantomSession;
  String _phantomPlayerColor = 'white';
  bool _showPhantomLb = false;
  List<Map<String, dynamic>> _daily = [];
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _phantomDaily = [];
  List<Map<String, dynamic>> _phantomHistory = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final today = await ApiService.getChessToday();
      final lb = await ApiService.getChessLeaderboard();
      Map<String, dynamic> pToday = {};
      Map<String, dynamic> pLb = {};
      try { pToday = await ApiService.getPhantomChessToday(); } catch (_) {}
      try { pLb = await ApiService.getPhantomChessLeaderboard(); } catch (_) {}
      if (mounted) setState(() {
        _botLevel = today['botLevel'] ?? 800;
        _played = today['played'] ?? false;
        _won = today['won'] == null ? null : (today['won'] == 1 || today['won'] == true);
        _moves = today['moves'];
        _session = today['session'];
        _playerColor = today['playerColor'] ?? 'white';
        _daily = List<Map<String, dynamic>>.from(lb['daily'] ?? []);
        _history = List<Map<String, dynamic>>.from(lb['history'] ?? []);
        _phantomBotLevel = pToday['botLevel'] ?? (_botLevel ~/ 2);
        _phantomPlayed = pToday['played'] ?? false;
        _phantomWon = pToday['won'] == null ? null : (pToday['won'] == 1 || pToday['won'] == true);
        _phantomMoves = pToday['moves'];
        _phantomSession = pToday['session'];
        _phantomPlayerColor = pToday['playerColor'] ?? 'white';
        _phantomDaily = List<Map<String, dynamic>>.from(pLb['daily'] ?? []);
        _phantomHistory = List<Map<String, dynamic>>.from(pLb['history'] ?? []);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_playingPhantom) {
      return PhantomGameScreen(
        botLevel: _phantomBotLevel,
        theme: widget.theme,
        session: _phantomSession,
        playerColor: _phantomPlayerColor,
        onFinish: (won, moves, redos, moveHistory) async {
          await ApiService.submitPhantomChessResult(won, moves, redos, moveHistory);
          setState(() { _playingPhantom = false; });
          _load();
        },
        onBack: () => setState(() { _playingPhantom = false; _load(); }),
      );
    }

    if (_playing) {
      return ChessGameScreen(
        botLevel: _botLevel,
        theme: widget.theme,
        session: _session,
        playerColor: _playerColor,
        onFinish: (won, moves, redos, moveHistory, fen) async {
          await ApiService.submitChessResult(won, moves, redos, moveHistory, fen);
          setState(() { _playing = false; });
          _load();
        },
        onBack: () => setState(() { _playing = false; _load(); }),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
            const Text('Chess.IT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          ]),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: _loading
                  ? const CircularProgressIndicator()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Game cards side by side
                          Row(
                            children: [
                              Expanded(child: _buildGameCard(
                                title: 'Normal',
                                elo: _botLevel,
                                played: _played,
                                won: _won,
                                moves: _moves,
                                hasSession: _session != null,
                                color: widget.theme.correct,
                                onPlay: () => setState(() => _playing = true),
                              )),
                              const SizedBox(width: 12),
                              Expanded(child: _buildGameCard(
                                title: 'Phantom',
                                elo: _phantomBotLevel,
                                played: _phantomPlayed,
                                won: _phantomWon,
                                moves: _phantomMoves,
                                hasSession: _phantomSession != null,
                                color: widget.theme.present,
                                onPlay: () => setState(() => _playingPhantom = true),
                              )),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity, height: 44,
                            child: ElevatedButton(
                              onPressed: () => showHelpDialog(context, widget.theme, 'How to Play Chess.IT', const [
                                HelpSection(body: 'Play chess against a daily bot. The bot level changes every day (100-1500 ELO).'),
                                HelpSection(heading: '♟️ One Chance', body: 'You get one game per day. Win or lose, your result goes on the leaderboard.'),
                                HelpSection(heading: '↩️ Redo Moves', body: 'You get 2 redo moves per game if you make a mistake. Use them wisely!'),
                                HelpSection(heading: '🏆 Scoring', body: 'Win with fewer moves to rank higher. Losses show ✗ on the leaderboard.'),
                              ]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3A3A3C),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('How to Play', style: TextStyle(fontSize: 16, color: Colors.white)),
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Divider(color: Color(0xFF3A3A3C)),
                          const SizedBox(height: 16),
                          // Leaderboard toggle buttons
                          Row(children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _showPhantomLb = false),
                                child: Container(
                                  height: 38,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: !_showPhantomLb ? widget.theme.present : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: widget.theme.present.withValues(alpha: 0.5)),
                                  ),
                                  child: Text('Normal', style: TextStyle(
                                    color: !_showPhantomLb ? Colors.white : widget.theme.present,
                                    fontWeight: FontWeight.bold, fontSize: 14,
                                  )),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _showPhantomLb = true),
                                child: Container(
                                  height: 38,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _showPhantomLb ? widget.theme.present : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: widget.theme.present.withValues(alpha: 0.5)),
                                  ),
                                  child: Text('Phantom', style: TextStyle(
                                    color: _showPhantomLb ? Colors.white : widget.theme.present,
                                    fontWeight: FontWeight.bold, fontSize: 14,
                                  )),
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 16),
                          const Text("Today's Leaderboard", style: TextStyle(color: Colors.grey, fontSize: 14)),
                          const SizedBox(height: 12),
                          if ((_showPhantomLb ? _phantomDaily : _daily).isEmpty)
                            const Text('No games yet today.', style: TextStyle(color: Colors.grey, fontSize: 14))
                          else
                            ...(_showPhantomLb ? _phantomDaily : _daily).asMap().entries.map((entry) {
                              final i = entry.key;
                              final row = entry.value;
                              final won = row['won'] == true;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1B),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF3A3A3C)),
                                ),
                                child: Row(children: [
                                  SizedBox(width: 28, child: Text('#${i + 1}', style: TextStyle(
                                    color: i == 0 ? widget.theme.correct : Colors.grey, fontWeight: FontWeight.bold,
                                  ))),
                                  Expanded(child: Text(row['nickname'] ?? '', style: const TextStyle(color: Colors.white))),
                                  Text(
                                    won ? '${row['moves']} moves ✓' : '✗',
                                    style: TextStyle(color: won ? widget.theme.correct : Colors.redAccent, fontWeight: FontWeight.bold),
                                  ),
                                ]),
                              );
                            }),
                          if ((_showPhantomLb ? _phantomHistory : _history).isNotEmpty) ...[
                            const SizedBox(height: 24),
                            const Divider(color: Color(0xFF3A3A3C)),
                            const SizedBox(height: 16),
                            const Text('Your History', style: TextStyle(color: Colors.grey, fontSize: 14)),
                            const SizedBox(height: 12),
                            ...(_showPhantomLb ? _phantomHistory : _history).map((row) {
                              final won = row['won'] == 1 || row['won'] == true;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1B),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF3A3A3C)),
                                ),
                                child: Row(children: [
                                  SizedBox(width: 90, child: Text(row['date'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12))),
                                  Text('Bot ${row['bot_level']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  const Spacer(),
                                  Text(
                                    won ? '${row['moves']} moves ✓' : '✗',
                                    style: TextStyle(color: won ? widget.theme.correct : Colors.redAccent, fontWeight: FontWeight.bold),
                                  ),
                                ]),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGameCard({
    required String title,
    required int elo,
    required bool played,
    required bool? won,
    required int? moves,
    required bool hasSession,
    required Color color,
    required VoidCallback onPlay,
  }) {
    return Column(
      children: [
        // ELO bar above card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Text('Bot: $elo ELO', textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        // Card
        GestureDetector(
          onTap: played ? null : onPlay,
          child: Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(title == 'Phantom' ? Icons.visibility_off : Icons.smart_toy, color: color, size: 30),
                const SizedBox(height: 8),
                Text(title, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (played)
                  Text(
                    won == true ? '$moves moves ✓' : '✗',
                    style: TextStyle(color: won == true ? widget.theme.correct : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  )
                else
                  Text(
                    hasSession ? 'Continue' : 'Play',
                    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
