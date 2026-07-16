import 'package:flutter/material.dart';

/// Help/rules modal for Deal.IT (Daily Solitaire).
class SolitaireHelpDialog extends StatelessWidget {
  const SolitaireHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1B),
      title: const Text(
        'How to Play Deal.IT',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\ud83c\udccf GOAL',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Move all 52 cards to the four foundation piles, '
              'building each suit up from Ace to King.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            SizedBox(height: 16),
            Text(
              '\ud83d\udccb RULES',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '\u2022 Tableau: Build down in alternating colors (red on black, black on red)\n'
              '\u2022 Foundation: Build up by suit (A \u2192 2 \u2192 3 \u2192 ... \u2192 K)\n'
              '\u2022 Stock: Tap to draw 3 cards. Only the top drawn card is playable.\n'
              '\u2022 Empty columns: Only a King can fill an empty column\n'
              '\u2022 Move stacks: You can move a sequence of face-up cards together',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
            ),
            SizedBox(height: 16),
            Text(
              '\ud83c\udfae CONTROLS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '\u2022 Tap a card to select it (amber highlight)\n'
              '\u2022 Tap a destination to move it there\n'
              '\u2022 Tap the stock pile to draw 3 cards\n'
              '\u2022 Tap the empty stock to recycle the waste pile\n'
              '\u2022 Aces auto-move to foundations',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
            ),
            SizedBox(height: 16),
            Text(
              '\u26a1 DAILY CHALLENGE',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '\u2022 Same deck for everyone \u2014 compare your skills!\n'
              '\u2022 One attempt per day \u2014 no undo, no restart\n'
              '\u2022 Timer starts on your first move',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
            ),
            SizedBox(height: 16),
            Text(
              '\ud83c\udfc6 SCORING (max 20 points)',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '\u2022 Completed: 10 pts | Tried: 1 pt\n'
              '\u2022 Under 2 min: +5 | Under 5 min: +3 | Under 10 min: +1\n'
              '\u2022 Under 80 moves: +5 | Under 120: +3 | Under 160: +1',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Got it!',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
