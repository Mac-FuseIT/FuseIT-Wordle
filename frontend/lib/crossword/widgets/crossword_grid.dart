import 'package:flutter/material.dart';
import 'dart:math';
import '../../models/app_theme.dart';

class CrosswordGrid extends StatefulWidget {
  final List<List<String?>> grid;
  final List<Map<String, dynamic>> cluesAcross;
  final List<Map<String, dynamic>> cluesDown;
  final int? selectedRow;
  final int? selectedCol;
  final bool isAcross;
  final Function(int row, int col) onCellTap;
  final AppTheme theme;
  final bool completed;
  final Set<String> correctCells;
  final bool shakeWord;

  const CrosswordGrid({
    super.key,
    required this.grid,
    required this.cluesAcross,
    required this.cluesDown,
    required this.selectedRow,
    required this.selectedCol,
    required this.isAcross,
    required this.onCellTap,
    required this.theme,
    this.completed = false,
    this.correctCells = const {},
    this.shakeWord = false,
  });

  @override
  State<CrosswordGrid> createState() => _CrosswordGridState();
}

class _CrosswordGridState extends State<CrosswordGrid> with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));
  }

  @override
  void didUpdateWidget(CrosswordGrid old) {
    super.didUpdateWidget(old);
    if (widget.shakeWord && !old.shakeWord) {
      _shakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Set<String> get _selectedWordCells {
    final cells = <String>{};
    if (widget.selectedRow == null || widget.selectedCol == null) return cells;
    final clues = widget.isAcross ? widget.cluesAcross : widget.cluesDown;
    for (final clue in clues) {
      final r = clue['row'] as int;
      final c = clue['col'] as int;
      final len = clue['length'] as int;
      if (widget.isAcross) {
        if (r == widget.selectedRow && widget.selectedCol! >= c && widget.selectedCol! < c + len) {
          for (int i = 0; i < len; i++) cells.add('$r:${c + i}');
          break;
        }
      } else {
        if (c == widget.selectedCol && widget.selectedRow! >= r && widget.selectedRow! < r + len) {
          for (int i = 0; i < len; i++) cells.add('${r + i}:$c');
          break;
        }
      }
    }
    return cells;
  }

  int? _getCellNumber(int row, int col) {
    for (final clue in [...widget.cluesAcross, ...widget.cluesDown]) {
      if (clue['row'] == row && clue['col'] == col) return clue['number'] as int;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final numRows = widget.grid.length;
    final numCols = widget.grid.isNotEmpty ? widget.grid[0].length : 0;
    final wordCells = _selectedWordCells;
    // Scale cell size based on grid dimensions
    final cellSize = numCols > 6 ? 40.0 : 48.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(numRows, (row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(numCols, (col) {
            final cell = widget.grid[row][col];
            // Blocked cell
            if (cell == null) {
              return Container(
                width: cellSize, height: cellSize,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: widget.theme.background,
                  border: Border.all(color: widget.theme.background, width: 1),
                ),
              );
            }

            final isSelected = row == widget.selectedRow && col == widget.selectedCol;
            final isInWord = wordCells.contains('$row:$col');
            final number = _getCellNumber(row, col);
            final hasLetter = cell.isNotEmpty;

            Color bg;
            if (widget.completed && hasLetter) {
              bg = widget.theme.correct.withValues(alpha: 0.3);
            } else if (widget.correctCells.contains('$row:$col')) {
              bg = widget.theme.correct.withValues(alpha: 0.6);
            } else if (isSelected) {
              bg = widget.theme.correct.withValues(alpha: 0.4);
            } else if (isInWord) {
              bg = widget.theme.correct.withValues(alpha: 0.15);
            } else {
              bg = widget.theme.tileEmpty;
            }

            Widget cellWidget = GestureDetector(
              onTap: () => widget.onCellTap(row, col),
              child: Container(
                width: cellSize, height: cellSize,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(color: isSelected ? widget.theme.correct : widget.theme.present, width: isSelected ? 2 : 1),
                ),
                child: Stack(
                  children: [
                    if (number != null)
                      Positioned(left: 2, top: 1, child: Text('$number', style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.5), fontSize: 9))),
                    Center(child: Text(cell.toUpperCase(), style: TextStyle(color: widget.theme.textColor, fontSize: cellSize > 44 ? 22 : 18, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
            );

            // Shake cells in the selected word
            if (isInWord && _shakeController.isAnimating) {
              cellWidget = AnimatedBuilder(
                animation: _shakeAnim,
                builder: (context, child) {
                  final offset = sin(_shakeAnim.value * 3 * pi) * 8;
                  return Transform.translate(offset: Offset(offset, 0), child: child);
                },
                child: cellWidget,
              );
            }

            return cellWidget;
          }),
        );
      }),
    );
  }
}
