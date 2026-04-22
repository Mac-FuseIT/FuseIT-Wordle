import 'package:flutter/material.dart';
import '../models/game_state.dart';

class LeaderboardTable extends StatelessWidget {
  final String title;
  final List<LeaderboardEntry> entries;
  final bool isMonthly;
  final Color accentColor;
  final String? currentUserName;

  const LeaderboardTable({
    super.key,
    required this.title,
    required this.entries,
    this.isMonthly = false,
    this.accentColor = const Color(0xFF6AAA64),
    this.currentUserName,
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
            final isMe = currentUserName != null && entry.name.toLowerCase() == currentUserName!.toLowerCase();
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isMe
                    ? accentColor.withValues(alpha: 0.25)
                    : i == 0
                        ? accentColor.withValues(alpha: 0.1)
                        : const Color(0xFF1A1A1B),
                borderRadius: BorderRadius.circular(4),
                border: isMe ? Border.all(color: accentColor.withValues(alpha: 0.6), width: 1) : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('${i + 1}.', style: TextStyle(color: isMe ? accentColor : Colors.grey, fontSize: 14, fontWeight: isMe ? FontWeight.bold : FontWeight.normal)),
                  ),
                  Expanded(child: Text(
                    isMe ? '${entry.name} (you)' : entry.name,
                    style: TextStyle(color: isMe ? Colors.white : Colors.white, fontSize: 14, fontWeight: isMe ? FontWeight.bold : FontWeight.normal),
                  )),
                  Text(
                    isMonthly ? '${entry.totalGuesses} total' : '${entry.numGuesses} ${entry.solved == true ? '✓' : '✗'}',
                    style: TextStyle(
                      color: isMe ? accentColor : (!isMonthly && entry.solved == true) ? accentColor : Colors.grey,
                      fontSize: 14,
                      fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
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
