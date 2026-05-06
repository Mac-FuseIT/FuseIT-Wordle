import 'package:flutter/material.dart';
import '../models/app_theme.dart';

class MainMenuScreen extends StatelessWidget {
  final String name;
  final AppTheme theme;
  final VoidCallback onGuessIT;
  final VoidCallback onCrossIT;
  final VoidCallback onGramIT;
  final VoidCallback onPongIT;
  final VoidCallback onInvadeIT;
  final VoidCallback onProfile;
  final VoidCallback onLogout;

  const MainMenuScreen({
    super.key,
    required this.name,
    required this.theme,
    required this.onGuessIT,
    required this.onCrossIT,
    required this.onGramIT,
    required this.onPongIT,
    required this.onInvadeIT,
    required this.onProfile,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Fuse Arcade', style: TextStyle(
              fontFamily: 'Trebuchet MS', color: theme.textColor, fontSize: 42, fontWeight: FontWeight.bold,
              shadows: [Shadow(color: theme.correct, blurRadius: 12), Shadow(color: theme.correct, blurRadius: 24)],
            )),
            const SizedBox(height: 8),
            Text('Daily games for FuseIT', style: TextStyle(color: theme.textColor.withValues(alpha: 0.5), fontSize: 14)),
            const SizedBox(height: 48),
            const SizedBox(height: 48),
            // Word Games
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Word Games', style: TextStyle(color: theme.textColor.withValues(alpha: 0.5), fontSize: 13, letterSpacing: 1)),
                const SizedBox(width: 12),
                SizedBox(width: 200, child: Divider(color: theme.textColor.withValues(alpha: 0.15))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GameCard(title: 'Guess.IT', subtitle: 'Daily word game', icon: Icons.abc, color: theme.correct, onTap: onGuessIT),
                const SizedBox(width: 16),
                _GameCard(title: 'Cross.IT', subtitle: 'Mini crossword', icon: Icons.grid_on, color: theme.present, onTap: onCrossIT),
                const SizedBox(width: 16),
                _GameCard(title: 'Span.IT', subtitle: 'Word strands', icon: Icons.link, color: theme.correct, onTap: onGramIT),
              ],
            ),
            const SizedBox(height: 32),
            // Arcade Games
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Arcade Games', style: TextStyle(color: theme.textColor.withValues(alpha: 0.5), fontSize: 13, letterSpacing: 1)),
                const SizedBox(width: 12),
                SizedBox(width: 200, child: Divider(color: theme.textColor.withValues(alpha: 0.15))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GameCard(title: 'Pong.IT', subtitle: 'Classic pong', icon: Icons.sports_esports, color: theme.present, onTap: onPongIT),
                const SizedBox(width: 16),
                _GameCard(title: 'Invade.IT', subtitle: 'Space invaders', icon: Icons.rocket_launch, color: theme.correct, onTap: onInvadeIT),
              ],
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onProfile,
                  child: Row(children: [
                    Text(name, style: TextStyle(color: theme.textColor.withValues(alpha: 0.6), fontSize: 14)),
                    const SizedBox(width: 4),
                    Icon(Icons.edit, color: theme.textColor.withValues(alpha: 0.4), size: 14),
                  ]),
                ),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: onLogout,
                  child: Row(children: [
                    Icon(Icons.logout, color: theme.textColor.withValues(alpha: 0.4), size: 16),
                    const SizedBox(width: 4),
                    Text('Logout', style: TextStyle(color: theme.textColor.withValues(alpha: 0.4), fontSize: 13)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _GameCard({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130, height: 150,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
