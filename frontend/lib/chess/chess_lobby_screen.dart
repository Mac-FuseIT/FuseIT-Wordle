import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/help_dialog.dart';
import 'chess_game_screen.dart';

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
  bool _played = false;
  bool? _won;
  int? _moves;
  int _botLevel = 800;
  Map<String, dynamic>? _session;
  List<Map<String, dynamic>> _daily = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final today = await ApiService.getChessToday();
      final lb = await ApiService.getChessLeaderboard();
      if (mounted) setState(() {
        _botLevel = today['botLevel'] ?? 800;
        _played = today['played'] ?? false;
        _won = today['won'] == null ? null : (today['won'] == 1 || today['won'] == true);
        _moves = today['moves'];
        _session = today['session'];
        _daily = List<Map<String, dynamic>>.from(lb['daily'] ?? []);
        _history = List<Map<String, dynamic>>.from(lb['history'] ?? []);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_playing) {
      return ChessGameScreen(
        botLevel: _botLevel,
        theme: widget.theme,
        session: _session,
        onFinish: (won, moves, redos) async {
          await ApiService.submitChessResult(won, moves, redos, [], '');
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
                          // Today's bot info
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF3A3A3C)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.smart_toy, color: Colors.white70, size: 20),
                              const SizedBox(width: 8),
                              Text("Today's Bot: $_botLevel ELO", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ]),
                          ),
                          const SizedBox(height: 16),
                          if (_played) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _won == true ? widget.theme.correct : Colors.redAccent),
                              ),
                              child: Row(children: [
                                Icon(_won == true ? Icons.check_circle : Icons.cancel,
                                    color: _won == true ? widget.theme.correct : Colors.redAccent, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _won == true ? 'Won in $_moves moves ✓' : 'Lost ✗',
                                  style: TextStyle(color: _won == true ? widget.theme.correct : Colors.redAccent, fontWeight: FontWeight.bold),
                                ),
                              ]),
                            ),
                          ] else ...[
                            SizedBox(
                              width: double.infinity, height: 44,
                              child: ElevatedButton(
                                onPressed: () => setState(() => _playing = true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.theme.correct,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(_session != null ? 'Continue' : 'Play', style: const TextStyle(fontSize: 16, color: Colors.white)),
                              ),
                            ),
                          ],
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
                          const Text('Today\'s Leaderboard', style: TextStyle(color: Colors.grey, fontSize: 14)),
                          const SizedBox(height: 12),
                          if (_daily.isEmpty)
                            const Text('No games yet today.', style: TextStyle(color: Colors.grey, fontSize: 14))
                          else
                            ..._daily.asMap().entries.map((entry) {
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
                          if (_history.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            const Divider(color: Color(0xFF3A3A3C)),
                            const SizedBox(height: 16),
                            const Text('Your History', style: TextStyle(color: Colors.grey, fontSize: 14)),
                            const SizedBox(height: 12),
                            ..._history.map((row) {
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
}
