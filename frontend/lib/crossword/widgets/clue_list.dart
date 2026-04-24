import 'package:flutter/material.dart';
import '../../models/app_theme.dart';

class ClueList extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> clues;
  final int? activeNumber;
  final Function(Map<String, dynamic>) onClueTap;
  final AppTheme theme;

  const ClueList({super.key, required this.title, required this.clues, this.activeNumber, required this.onClueTap, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: theme.textColor, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ...clues.map((clue) {
          final isActive = clue['number'] == activeNumber;
          return GestureDetector(
            onTap: () => onClueTap(clue),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: isActive ? theme.correct.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${clue['number']}. ${clue['clue']}',
                style: TextStyle(color: isActive ? theme.correct : theme.textColor.withValues(alpha: 0.8), fontSize: 13),
              ),
            ),
          );
        }),
      ],
    );
  }
}
