import 'package:flutter/material.dart';
import '../../models/app_theme.dart';

/// Roulette game screen. Full implementation in a separate task.
class RouletteScreen extends StatelessWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final String nickname;
  final int userId;

  const RouletteScreen({
    super.key,
    required this.theme,
    required this.onBack,
    required this.nickname,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
              ),
              const Text(
                'Roulette',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        const Expanded(
          child: Center(
            child: Text(
              'Coming soon…',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
