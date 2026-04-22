import 'package:flutter/material.dart';
import '../models/game_state.dart';

class GameKeyboard extends StatelessWidget {
  final Function(String) onKey;
  final VoidCallback onEnter;
  final VoidCallback onBackspace;
  final List<GuessResult> guesses;
  final Color correctColor;
  final Color presentColor;
  final Color absentColor;
  final Color keyDefault;

  const GameKeyboard({
    super.key,
    required this.onKey,
    required this.onEnter,
    required this.onBackspace,
    required this.guesses,
    this.correctColor = const Color(0xFF6AAA64),
    this.presentColor = const Color(0xFFC9B458),
    this.absentColor = const Color(0xFF3A3A3C),
    this.keyDefault = const Color(0xFF818384),
  });

  static const _rows = [
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['ENTER', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '⌫'],
  ];

  Map<String, String> get _letterStatuses {
    final map = <String, String>{};
    for (final g in guesses) {
      for (final r in g.result) {
        final key = r.letter.toUpperCase();
        final existing = map[key];
        if (r.status == 'correct') {
          map[key] = 'correct';
        } else if (r.status == 'present' && existing != 'correct') {
          map[key] = 'present';
        } else if (existing == null) {
          map[key] = 'absent';
        }
      }
    }
    return map;
  }

  Color _keyColor(String key) {
    final status = _letterStatuses[key];
    switch (status) {
      case 'correct': return correctColor;
      case 'present': return presentColor;
      case 'absent': return absentColor;
      default: return keyDefault;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _rows.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              final isWide = key == 'ENTER' || key == '⌫';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: SizedBox(
                  width: isWide ? 65 : 40,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      if (key == 'ENTER') { onEnter(); }
                      else if (key == '⌫') { onBackspace(); }
                      else { onKey(key.toLowerCase()); }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _keyColor(key),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(key, style: TextStyle(fontSize: isWide ? 12 : 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
