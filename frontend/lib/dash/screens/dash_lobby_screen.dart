import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/app_theme.dart';
import '../../widgets/help_dialog.dart';
import '../models/level.dart';
import 'dash_game_screen.dart';

class DashLobbyScreen extends StatefulWidget {
  final String nickname;
  final int userId;
  final AppTheme theme;
  final VoidCallback onBack;

  const DashLobbyScreen({
    super.key,
    required this.nickname,
    required this.userId,
    required this.theme,
    required this.onBack,
  });

  @override
  State<DashLobbyScreen> createState() => _DashLobbyScreenState();
}

class _DashLobbyScreenState extends State<DashLobbyScreen> {
  List<Map<String, dynamic>> _leaderboard = [];
  bool _loading = true;
  bool _playing = false;
  DashLevel? _level;
  String? _error;
  String _zoneName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('/api/dash/today'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final levelJson = data['level'] as Map<String, dynamic>;
        _level = DashLevel.fromJson(levelJson);
        _zoneName = _level!.zoneName;
      } else {
        _error = 'No level available today.';
      }
    } catch (e) {
      _error = 'Failed to load level.';
    }
    try {
      final res = await http.get(Uri.parse('/api/dash/leaderboard'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _leaderboard = List<Map<String, dynamic>>.from(data['leaderboard'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_playing && _level != null) {
      return DashGameScreen(
        nickname: widget.nickname,
        userId: widget.userId,
        theme: widget.theme,
        level: _level!,
        onBack: () => setState(() { _playing = false; _load(); }),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
              const Text('Dash.IT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_error != null)
                      Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
                    else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF3A3A3C)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.map, color: widget.theme.correct, size: 20),
                            const SizedBox(width: 8),
                            Text("Today's Zone: ${_zoneName.toUpperCase()}",
                                style: TextStyle(color: widget.theme.correct, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () => setState(() => _playing = true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.theme.correct,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Play', style: TextStyle(fontSize: 16, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () => showHelpDialog(context, widget.theme, 'How to Play Dash.IT', const [
                            HelpSection(body: 'A daily side-scrolling platformer. Complete the level as fast as possible to top the leaderboard!'),
                            HelpSection(heading: '← → Arrow Keys', body: 'Move left and right.'),
                            HelpSection(heading: '↑ / Space', body: 'Jump.'),
                            HelpSection(heading: '↓', body: 'Duck or enter a warp pipe.'),
                            HelpSection(heading: '🪙 Coins', body: 'Collect coins for +10 points each.'),
                            HelpSection(heading: '❓ Question Blocks', body: 'Hit from below to reveal power-ups or coins.'),
                            HelpSection(heading: '👾 Enemies', body: 'Jump on most enemies to defeat them. Spiny and Piranha Plants require fireballs.'),
                            HelpSection(heading: '🏆 Scoring', body: 'Complete the level for 1000 pts + time bonus + lives bonus. Only completions appear on the leaderboard.'),
                          ]),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3A3A3C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('How to Play', style: TextStyle(fontSize: 16, color: Colors.white)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    const Divider(color: Color(0xFF3A3A3C)),
                    const SizedBox(height: 16),
                    const Text('Today\'s Leaderboard', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 12),
                    if (_leaderboard.isEmpty)
                      const Text('No completions yet. Be the first!', style: TextStyle(color: Colors.grey, fontSize: 14))
                    else
                      ..._leaderboard.asMap().entries.map((entry) {
                        final i = entry.key;
                        final row = entry.value;
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
                                child: Text('#${i + 1}', style: TextStyle(
                                  color: i == 0 ? widget.theme.correct : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                )),
                              ),
                              Expanded(child: Text(row['nickname'] ?? '', style: const TextStyle(color: Colors.white))),
                              Text('${row['score']}', style: TextStyle(color: widget.theme.correct, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 12),
                              Text('${row['time_seconds']}s', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(width: 8),
                              Text('🪙${row['coins']}', style: TextStyle(color: widget.theme.present, fontSize: 12)),
                            ],
                          ),
                        );
                      }),
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
