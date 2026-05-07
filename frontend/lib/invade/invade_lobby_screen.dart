import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/help_dialog.dart';
import 'invade_game_screen.dart';

class InvadeLobbyScreen extends StatefulWidget {
  final String nickname;
  final int userId;
  final AppTheme theme;
  final VoidCallback onBack;

  const InvadeLobbyScreen({
    super.key,
    required this.nickname,
    required this.userId,
    required this.theme,
    required this.onBack,
  });

  @override
  State<InvadeLobbyScreen> createState() => _InvadeLobbyScreenState();
}

class _InvadeLobbyScreenState extends State<InvadeLobbyScreen> {
  List<Map<String, dynamic>> _leaderboard = [];
  int _myBest = 0;
  bool _loading = true;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    try {
      final data = await ApiService.getInvadeLeaderboard();
      if (mounted) setState(() {
        _leaderboard = List<Map<String, dynamic>>.from(data['leaderboard'] ?? []);
        _myBest = data['best'] ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_playing) {
      return InvadeGameScreen(
        nickname: widget.nickname,
        userId: widget.userId,
        theme: widget.theme,
        onBack: () => setState(() { _playing = false; _loadLeaderboard(); }),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
              const Text('Invade.IT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
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
                    if (_myBest > 0) ...[
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
                            Icon(Icons.emoji_events, color: widget.theme.correct, size: 20),
                            const SizedBox(width: 8),
                            Text('Your Best: $_myBest', style: TextStyle(color: widget.theme.correct, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
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
                        onPressed: () => showHelpDialog(context, widget.theme, 'How to Play Invade.IT', const [
                          HelpSection(body: 'Enemy ships spawn from the top of the screen and move around randomly. Destroy them before they destroy you!'),
                          HelpSection(heading: '← → ↑ ↓ Arrow Keys', body: 'Move your ship freely in all directions across the entire screen.'),
                          HelpSection(heading: '🚀 Shooting', body: 'Hold down Spacebar to shoot. When your shots run out, release Spacebar and hold it again to fire another burst.'),
                          HelpSection(heading: '👾 Enemy Tiers', body: 'Grunt (grey) — 10 pts, easy.\nSoldier (yellow) — 25 pts, shoots faster.\nCommander (green) — 50 pts, takes 2 hits, most aggressive.'),
                          HelpSection(heading: '❤️ Lives', body: 'You start with 2 lives shown as hearts at the bottom of the screen. Getting hit loses a life. Reaching a new level tops you up to 2 hearts — but if you already have more, you keep them.'),
                          HelpSection(heading: '➕ Health Packs', body: 'A red cross occasionally drops from the top of the screen. Fly over it to collect it and gain 1 extra heart. Don\'t let it drift past you!'),
                          HelpSection(heading: '⬆️ Levels', body: 'Destroy 10+ enemies to reach the next level. Each level spawns enemies faster and with tougher tiers.'),
                          HelpSection(heading: '🏆 Score', body: 'Your highest score is saved to the leaderboard. Clearing a wave gives a +100 bonus.'),
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
                    const Text('Leaderboard', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_leaderboard.isEmpty)
                      const Text('No scores yet. Be the first!', style: TextStyle(color: Colors.grey, fontSize: 14))
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
                              Text('Lvl ${row['level_reached']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
