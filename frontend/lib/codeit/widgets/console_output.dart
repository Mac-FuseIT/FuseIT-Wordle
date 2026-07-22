import 'package:flutter/material.dart';

/// The three visual states the console can be in.
enum ConsoleType {
  /// Neutral white text — used for partial match counts.
  info,

  /// Green text — used on a perfect solve.
  success,

  /// Red text — used for DSL parse / runtime errors.
  error,
}

/// A one-line or multi-line output panel shown below the Run/Reset buttons.
///
/// Colours:
/// - [ConsoleType.info]    → white text, muted border
/// - [ConsoleType.success] → #2ECC71 text, green tinted border
/// - [ConsoleType.error]   → #E74C3C text, red tinted border
class ConsoleOutput extends StatelessWidget {
  final String message;
  final ConsoleType type;

  const ConsoleOutput({
    super.key,
    required this.message,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      ConsoleType.info => Colors.white,
      ConsoleType.success => const Color(0xFF2ECC71),
      ConsoleType.error => const Color(0xFFE74C3C),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontFamily: 'Courier New',
        ),
      ),
    );
  }
}
