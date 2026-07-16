import 'package:flutter/material.dart';
import '../../models/app_theme.dart';

/// A single playing card widget.
///
/// Handles face-up, face-down, selected, and empty slot states.
class PlayingCard extends StatelessWidget {
  /// Card code, e.g. "Ah" (Ace of hearts), "10s" (10 of spades). Null for empty slot.
  final String? card;

  /// Whether to render the card face-down (back side shown).
  final bool faceDown;

  /// Whether the card is currently selected (amber highlight border).
  final bool selected;

  /// Whether this slot is empty (dashed outline placeholder).
  final bool isEmpty;

  /// Tap callback.
  final VoidCallback? onTap;

  /// App theme for color values.
  final AppTheme theme;

  const PlayingCard({
    super.key,
    this.card,
    this.faceDown = false,
    this.selected = false,
    this.isEmpty = false,
    this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (isEmpty) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 50,
          height: 70,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white24,
              style: BorderStyle.solid,
            ),
          ),
        ),
      );
    }

    if (faceDown) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 50,
          height: 70,
          decoration: BoxDecoration(
            color: theme.correct,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Center(
            child: Container(
              width: 36,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white24),
              ),
            ),
          ),
        ),
      );
    }

    // Face-up card — card must be non-null here.
    final rank = _getRank(card!);
    final suit = _getSuit(card!);
    final suitSymbol = _getSuitSymbol(suit);
    final isRed = suit == 'h' || suit == 'd';
    final pipColor = isRed ? Colors.red : Colors.black;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? theme.present : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: theme.present.withOpacity(0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              rank,
              style: TextStyle(
                color: pipColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              suitSymbol,
              style: TextStyle(color: pipColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the rank portion of a card code (everything except the last char).
  String _getRank(String card) => card.substring(0, card.length - 1);

  /// Returns the suit letter (last character of card code).
  String _getSuit(String card) => card.substring(card.length - 1);

  /// Maps a suit letter to its Unicode symbol.
  String _getSuitSymbol(String suit) {
    switch (suit) {
      case 'h':
        return '\u2665'; // ♥
      case 'd':
        return '\u2666'; // ♦
      case 'c':
        return '\u2663'; // ♣
      case 's':
        return '\u2660'; // ♠
      default:
        return '';
    }
  }
}
