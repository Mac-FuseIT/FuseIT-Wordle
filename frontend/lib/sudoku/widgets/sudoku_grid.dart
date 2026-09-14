// 9×9 Sudoku grid widget for Sudo.IT.
//
// Renders all 81 cells with proper 3×3 box borders, selection highlights,
// conflict tinting, notes (pencil marks), and given-cell styling.
// Sizing is responsive — adapts to available width with a 500 px cap.

import 'package:flutter/material.dart';

import '../../models/app_theme.dart';

// ---------------------------------------------------------------------------
// SudokuGrid
// ---------------------------------------------------------------------------

/// A stateless widget that renders the full 9×9 Sudoku board.
///
/// **Props:**
/// - [board]        — 81 values (0 = empty, 1–9 = digit).
/// - [puzzle]       — 81 values of the original clues. Non-zero cells are
///                    immutable givens.
/// - [notes]        — 81 [Set<int>] entries; pencil marks per cell.
/// - [conflicts]    — indices of cells that violate a row/col/box constraint.
/// - [selectedCell] — currently highlighted cell index, or `null`.
/// - [onCellTap]    — called with the tapped cell index.
/// - [theme]        — [AppTheme] for all colour choices.
///
/// **Layout:**
/// Uses a [LayoutBuilder] so the grid always fits inside its parent.
/// The maximum rendered width is capped at 500 px. Each cell is a square
/// whose side equals `(totalWidth) / 9`.
///
/// **Border convention:**
/// - 2 px thick between 3×3 boxes (every 3rd divider).
/// - 0.5 px thin between individual cells within a box.
class SudokuGrid extends StatelessWidget {
  final List<int> board;
  final List<int> puzzle;
  final List<Set<int>> notes;
  final Set<int> conflicts;
  final int? selectedCell;
  final ValueChanged<int> onCellTap;
  final AppTheme theme;

  /// Outer padding consumed by the centering column — subtracted from the
  /// available width when computing cell size.
  static const double _outerPadding = 16.0;

  /// Maximum overall grid width in logical pixels.
  static const double _maxGridWidth = 500.0;

  const SudokuGrid({
    super.key,
    required this.board,
    required this.puzzle,
    required this.notes,
    required this.conflicts,
    required this.selectedCell,
    required this.onCellTap,
    required this.theme,
  })  : assert(board.length == 81, 'board must have 81 elements'),
        assert(puzzle.length == 81, 'puzzle must have 81 elements'),
        assert(notes.length == 81, 'notes must have 81 elements');

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute cell size: fit inside available width, cap at max grid width.
        final availableWidth = constraints.maxWidth - _outerPadding;
        final gridWidth =
            availableWidth.clamp(0.0, _maxGridWidth);
        final cellSize = gridWidth / 9;

        return Center(
          child: SizedBox(
            width: gridWidth,
            height: gridWidth, // Grid is always square.
            child: _buildGrid(cellSize),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Grid assembly
  // -------------------------------------------------------------------------

  /// Builds the 9×9 grid as a [Column] of 9 [Row]s.
  ///
  /// Borders are achieved by wrapping each cell in a [Container] with
  /// selective [Border] widths: thick (2 px) on box edges, thin (0.5 px)
  /// on inner cell edges.  The outermost edge always uses the thick width.
  Widget _buildGrid(double cellSize) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(9, (row) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(9, (col) {
            final index = row * 9 + col;
            return _buildCell(index, row, col, cellSize);
          }),
        );
      }),
    );
  }

  // -------------------------------------------------------------------------
  // Cell widget
  // -------------------------------------------------------------------------

  Widget _buildCell(int index, int row, int col, double cellSize) {
    final borderColor = theme.textColor.withValues(alpha: 0.35);

    // --- Border thickness ---
    // Left border: thick if at box boundary (col % 3 == 0), else thin.
    // Top border: thick if at box boundary (row % 3 == 0), else thin.
    // Right border: always thin (next cell provides the left thick border)
    //   except the last column uses a thick right border for the outer edge.
    // Bottom border: always thin except last row uses thick.
    const double thick = 2.0;
    const double thin = 0.5;

    final leftWidth = col % 3 == 0 ? thick : thin;
    final topWidth = row % 3 == 0 ? thick : thin;
    final rightWidth = col == 8 ? thick : thin;
    final bottomWidth = row == 8 ? thick : thin;

    return GestureDetector(
      onTap: () => onCellTap(index),
      child: Container(
        width: cellSize,
        height: cellSize,
        decoration: BoxDecoration(
          color: _cellBackgroundColor(index),
          border: Border(
            left: BorderSide(color: borderColor, width: leftWidth),
            top: BorderSide(color: borderColor, width: topWidth),
            right: BorderSide(color: borderColor, width: rightWidth),
            bottom: BorderSide(color: borderColor, width: bottomWidth),
          ),
        ),
        child: _cellContent(index, cellSize),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Cell background colour
  // -------------------------------------------------------------------------

  /// Returns the background [Color] for [index] based on selection state,
  /// conflict state, and whether the cell shares the selected row/col/box
  /// or the same digit as the selected cell.
  Color _cellBackgroundColor(int index) {
    final isConflict = conflicts.contains(index);
    final isSelected = index == selectedCell;

    // Conflict always wins over selection highlights.
    if (isConflict) {
      return Colors.red.withValues(alpha: 0.3);
    }

    if (isSelected) {
      return theme.correct.withValues(alpha: 0.3);
    }

    if (selectedCell != null) {
      // Same-digit highlight (non-zero digit that matches the selected cell).
      final selectedDigit = board[selectedCell!];
      if (selectedDigit != 0 && board[index] == selectedDigit) {
        return theme.correct.withValues(alpha: 0.15);
      }

      // Same row/col/box highlight.
      if (_isPeer(index, selectedCell!)) {
        return theme.correct.withValues(alpha: 0.1);
      }
    }

    // Given cells get a marginally brighter tint so they feel "solid".
    if (puzzle[index] != 0) {
      // Nudge the blue channel slightly to create a subtle given-cell tint
      // that is theme-neutral (works across all AppTheme variants).
      final bg = theme.background;
      return bg.withValues(
        red: bg.r,
        green: bg.g,
        blue: (bg.b + 12.0 / 255.0).clamp(0.0, 1.0),
      );
    }

    return theme.background;
  }

  // -------------------------------------------------------------------------
  // Cell content
  // -------------------------------------------------------------------------

  /// Returns the inner widget for a cell: a digit, notes grid, or empty.
  Widget _cellContent(int index, double cellSize) {
    final value = board[index];
    final cellNotes = notes[index];

    if (value != 0) {
      // Cell has a placed digit.
      return _digitWidget(index, value, cellSize);
    }

    if (cellNotes.isNotEmpty) {
      // Cell has pencil marks but no digit.
      return _notesWidget(cellNotes, cellSize);
    }

    // Empty cell — nothing to render inside.
    return const SizedBox.shrink();
  }

  // -------------------------------------------------------------------------
  // Digit rendering
  // -------------------------------------------------------------------------

  /// Renders the digit [value] in the cell at [index].
  ///
  /// - Given cells: bold [AppTheme.textColor].
  /// - Conflict cells: red text.
  /// - Player-entered cells: [AppTheme.correct] text.
  Widget _digitWidget(int index, int value, double cellSize) {
    final isGiven = puzzle[index] != 0;
    final isConflict = conflicts.contains(index);

    final Color textColor;
    if (isConflict) {
      textColor = Colors.red;
    } else if (isGiven) {
      textColor = theme.textColor;
    } else {
      textColor = theme.correct;
    }

    final fontSize = (cellSize * 0.52).clamp(10.0, 32.0);

    return Center(
      child: Text(
        value.toString(),
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: isGiven ? FontWeight.bold : FontWeight.w500,
          height: 1.0,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Notes rendering
  // -------------------------------------------------------------------------

  /// Renders pencil marks as a 3×3 sub-grid of small digits inside the cell.
  ///
  /// Only digits present in [cellNotes] are shown; the rest are invisible
  /// placeholders that keep the layout stable.
  Widget _notesWidget(Set<int> cellNotes, double cellSize) {
    final noteColor = theme.textColor.withValues(alpha: 0.5);
    // Target roughly 1/3 of the cell height per note row, capped sensibly.
    final noteFontSize = (cellSize * 0.27).clamp(6.0, 14.0);

    return GridView.count(
      crossAxisCount: 3,
      physics: const NeverScrollableScrollPhysics(),
      // Remove default GridView padding so digits align to cell edges.
      padding: EdgeInsets.all(cellSize * 0.02),
      childAspectRatio: 1.0,
      children: List.generate(9, (i) {
        final digit = i + 1; // digits 1–9
        final visible = cellNotes.contains(digit);
        return Center(
          child: Text(
            visible ? digit.toString() : '',
            style: TextStyle(
              color: noteColor,
              fontSize: noteFontSize,
              fontWeight: FontWeight.w400,
              height: 1.0,
            ),
          ),
        );
      }),
    );
  }

  // -------------------------------------------------------------------------
  // Peer detection
  // -------------------------------------------------------------------------

  /// Returns `true` if [a] and [b] share the same row, column, or 3×3 box.
  bool _isPeer(int a, int b) {
    if (a == b) return false;
    final rowA = a ~/ 9, colA = a % 9;
    final rowB = b ~/ 9, colB = b % 9;
    if (rowA == rowB) return true;
    if (colA == colB) return true;
    final boxA = (rowA ~/ 3) * 3 + (colA ~/ 3);
    final boxB = (rowB ~/ 3) * 3 + (colB ~/ 3);
    return boxA == boxB;
  }
}
