import 'package:flutter/material.dart';

/// A 5×5 grid of colored cells for Code.IT.
///
/// [grid] is a column-major list: `grid[x][y]` where x is the column (0–4)
/// and y is the row (0–4).  Each value is a lowercase color name.
///
/// [matchOverlay] uses the same indexing.  When provided:
/// - `true`  → draw a green border (cell matches target)
/// - `false` → draw a red border (cell does not match target)
/// - `null` matchOverlay → no overlay borders
class PixelGrid extends StatelessWidget {
  final List<List<String>> grid; // 5×5 color strings [x][y]
  final List<List<bool>>? matchOverlay; // optional overlay after comparison
  final String label;

  const PixelGrid({
    super.key,
    required this.grid,
    this.matchOverlay,
    required this.label,
  });

  static const _colorMap = {
    'black': Color(0xFF000000),
    'red': Color(0xFFE74C3C),
    'blue': Color(0xFF3498DB),
    'yellow': Color(0xFFF1C40F),
    'green': Color(0xFF2ECC71),
    'white': Color(0xFFFFFFFF),
    'purple': Color(0xFF9B59B6),
    'orange': Color(0xFFE67E22),
  };

  static const _matchBorder = Color(0xFF2ECC71);
  static const _mismatchBorder = Color(0xFFE74C3C);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (y) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (x) {
                  final color = _colorMap[grid[x][y]] ?? Colors.black;
                  final match = matchOverlay?[x][y];
                  return Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                      border: match == true
                          ? Border.all(color: _matchBorder, width: 1.5)
                          : match == false
                              ? Border.all(color: _mismatchBorder, width: 1.5)
                              : Border.all(
                                  color: const Color(0xFF333333),
                                  width: 0.5,
                                ),
                    ),
                  );
                }),
              );
            }),
          ),
        ),
      ],
    );
  }
}
