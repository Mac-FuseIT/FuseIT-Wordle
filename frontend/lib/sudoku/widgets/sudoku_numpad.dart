import 'package:flutter/material.dart';
import '../../models/app_theme.dart';

/// Number pad and action buttons for the Sudo.IT game.
///
/// Displays digit buttons 1–9 in two rows ([1–5] and [6–9]) and three action
/// buttons (Notes toggle, Undo, Erase) below them. Digits that are fully
/// placed on the board (all 9 instances) are visually dimmed.
class SudokuNumpad extends StatelessWidget {
  /// Called when the player taps a digit button (1–9).
  final Function(int) onNumber;

  /// Toggles notes (pencil-marks) mode.
  final VoidCallback onNotes;

  /// Reverts the last action.
  final VoidCallback onUndo;

  /// Clears the selected cell.
  final VoidCallback onErase;

  /// Whether notes mode is currently active.
  final bool notesMode;

  /// The current player board (81 integers, 0 = empty, 1–9 = digit).
  /// Used to determine which digits are fully placed (dim those buttons).
  final List<int> board;

  /// App-wide colour theme.
  final AppTheme theme;

  const SudokuNumpad({
    super.key,
    required this.onNumber,
    required this.onNotes,
    required this.onUndo,
    required this.onErase,
    required this.notesMode,
    required this.board,
    required this.theme,
  });

  /// Returns the count of [digit] appearances on the board.
  int _countDigit(int digit) => board.where((v) => v == digit).length;

  /// Returns true when all 9 instances of [digit] are placed.
  bool _isFullyPlaced(int digit) => _countDigit(digit) >= 9;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Row 1: digits 1–5 ──────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [1, 2, 3, 4, 5]
              .map((n) => _NumberButton(
                    digit: n,
                    onTap: () => onNumber(n),
                    dimmed: _isFullyPlaced(n),
                    theme: theme,
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        // ── Row 2: digits 6–9 ─────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [6, 7, 8, 9]
              .map((n) => _NumberButton(
                    digit: n,
                    onTap: () => onNumber(n),
                    dimmed: _isFullyPlaced(n),
                    theme: theme,
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        // ── Action buttons row ─────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionButton(
              icon: Icons.edit,
              label: 'Notes',
              active: notesMode,
              activeColor: theme.correct,
              theme: theme,
              onTap: onNotes,
            ),
            const SizedBox(width: 12),
            _ActionButton(
              icon: Icons.undo,
              label: 'Undo',
              active: false,
              activeColor: theme.correct,
              theme: theme,
              onTap: onUndo,
            ),
            const SizedBox(width: 12),
            _ActionButton(
              icon: Icons.close,
              label: 'Erase',
              active: false,
              activeColor: theme.correct,
              theme: theme,
              onTap: onErase,
            ),
          ],
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Private helpers
// ──────────────────────────────────────────────────────────────────────────────

/// A single rounded-square digit button (1–9).
class _NumberButton extends StatelessWidget {
  final int digit;
  final VoidCallback onTap;
  final bool dimmed;
  final AppTheme theme;

  const _NumberButton({
    required this.digit,
    required this.onTap,
    required this.dimmed,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = theme.keyDefault;
    final textColor = dimmed
        ? theme.textColor.withValues(alpha: 0.25)
        : theme.textColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: dimmed ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: dimmed ? bgColor.withValues(alpha: 0.35) : bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            '$digit',
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// An action button (Notes / Undo / Erase) with an icon and a text label.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final AppTheme theme;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = active ? activeColor.withValues(alpha: 0.2) : theme.keyDefault;
    final fgColor = active ? activeColor : theme.textColor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: active
              ? Border.all(color: activeColor, width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fgColor, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: fgColor,
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
