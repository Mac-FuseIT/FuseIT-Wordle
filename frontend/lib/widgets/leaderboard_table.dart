import 'package:flutter/material.dart';
import '../models/game_state.dart';

class LeaderboardTable extends StatelessWidget {
  final String title;
  final List<LeaderboardEntry> entries;
  final bool isMonthly;

  const LeaderboardTable({
    super.key,
    required this.title,
    required this.entries,
    this.isMonthly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Text('No entries yet', style: TextStyle(color: Colors.grey))
        else
          ...entries.asMap().entries.map((e) {
            final i = e.key;
            final entry = e.value;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: i == 0 ? const Color(0xFF6AAA64).withValues(alpha: 0.2) : const Color(0xFF1A1A1B),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('${i + 1}.', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  ),
                  Expanded(child: Text(entry.name, style: const TextStyle(color: Colors.white, fontSize: 14))),
                  Text(
                    isMonthly ? '${entry.totalGuesses} total' : '${entry.numGuesses} ${entry.solved == true ? '✓' : '✗'}',
                    style: TextStyle(
                      color: (!isMonthly && entry.solved == true) ? const Color(0xFF6AAA64) : Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
