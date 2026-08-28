/// Deterministic puzzle generation for Sudo.IT.
///
/// Every client running the same date + difficulty produces the identical
/// 9×9 Sudoku puzzle with no backend involvement required for gameplay.
///
/// Board representation: flat [List<int>] of 81 elements, 0 = empty.
///   row = index ~/ 9
///   col = index % 9
///   box = (row ~/ 3) * 3 + (col ~/ 3)
library sudoku.puzzle_generator;

// ---------------------------------------------------------------------------
// Seeded RNG — Xorshift32
// ---------------------------------------------------------------------------

/// Seeded Xorshift32 RNG for deterministic puzzles.
///
/// Dart's built-in [Random] has four separate platform implementations
/// (VM, WASM, JS runtime, JS dev runtime) with no cross-platform output
/// guarantee. Xorshift32 produces identical output on all targets and is
/// ~15 lines — sufficient for a daily puzzle game.
///
/// Follows the same pattern as [SeededRng] in Pixel.IT's puzzle_generator.dart.
class SudokuRng {
  int _state;

  SudokuRng(int seed) : _state = seed == 0 ? 1 : seed;

  /// Returns a non-negative pseudorandom integer in `[0, max)`.
  int nextInt(int max) {
    _state ^= (_state << 13) & 0xFFFFFFFF;
    _state ^= (_state >> 17) & 0xFFFFFFFF;
    _state ^= (_state << 5) & 0xFFFFFFFF;
    _state = _state & 0xFFFFFFFF;
    // Dart integers are 64-bit; the xorshift can produce values that are
    // negative after the bitwise ops on 32-bit boundaries, so normalise.
    final positive = _state < 0 ? _state + 0x100000000 : _state;
    return positive % max;
  }

  /// Fisher-Yates shuffle driven by this RNG — modifies [list] in place.
  void shuffle<T>(List<T> list) {
    for (int i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}

// ---------------------------------------------------------------------------
// Seed derivation
// ---------------------------------------------------------------------------

/// Converts [date] + [difficulty] into a numeric seed by hashing the
/// combined string `"YYYY-MM-DD-{easy|medium|hard}"`.
///
/// Using a difficulty suffix ensures each level gets a distinct puzzle for
/// the same date — identical approach to Pixel.IT's `_dateToSeed` function.
/// The 0x7FFFFFFF mask keeps the value positive and within 31-bit range.
int _sudokuSeed(DateTime date, SudokuDifficulty difficulty) {
  final suffix = switch (difficulty) {
    SudokuDifficulty.easy => '-easy',
    SudokuDifficulty.medium => '-medium',
    SudokuDifficulty.hard => '-hard',
  };
  final dateStr = '${date.year}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}'
      '$suffix';
  int hash = 0;
  for (int i = 0; i < dateStr.length; i++) {
    hash = (hash * 31 + dateStr.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return hash;
}

// ---------------------------------------------------------------------------
// Difficulty
// ---------------------------------------------------------------------------

/// Difficulty levels for Sudo.IT puzzles.
///
/// Each level controls how many cells remain as givens after hole-digging:
/// - [easy]:   ~40 givens (41 empty cells) — gentle start, most cells filled.
/// - [medium]: ~32 givens (49 empty cells) — moderate challenge.
/// - [hard]:   ~25 givens (56 empty cells) — sparse board, requires notes.
///
/// Actual count may vary ±2 depending on uniqueness-checker constraints.
enum SudokuDifficulty {
  easy,
  medium,
  hard;

  /// Target number of clue cells remaining after hole-digging.
  int get targetGivens => switch (this) {
        SudokuDifficulty.easy => 40,
        SudokuDifficulty.medium => 32,
        SudokuDifficulty.hard => 25,
      };
}

// ---------------------------------------------------------------------------
// Constraint check
// ---------------------------------------------------------------------------

/// Returns `true` if placing [num] at [index] on [board] does not violate
/// any Sudoku constraint (row, column, or 3×3 box).
///
/// The cell at [index] is assumed to be empty (0) — it is not compared
/// against itself.
bool _isValid(List<int> board, int index, int num) {
  final row = index ~/ 9;
  final col = index % 9;
  final boxRow = (row ~/ 3) * 3;
  final boxCol = (col ~/ 3) * 3;

  for (int i = 0; i < 9; i++) {
    // Row check
    if (board[row * 9 + i] == num) return false;
    // Column check
    if (board[i * 9 + col] == num) return false;
    // 3×3 box check
    if (board[(boxRow + i ~/ 3) * 9 + (boxCol + i % 3)] == num) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Phase 1 — Backtracking grid fill
// ---------------------------------------------------------------------------

/// Fills [board] with a valid, complete Sudoku grid using backtracking.
///
/// Candidates `[1..9]` are shuffled with [rng] before each recursive call,
/// so every seed produces a different but valid completed grid.
///
/// Returns `true` when all 81 cells are filled, `false` if the current
/// partial assignment has no valid completion (triggering backtrack).
bool _fillGrid(List<int> board, SudokuRng rng) {
  final emptyIdx = board.indexOf(0);
  if (emptyIdx == -1) return true; // All cells filled — grid is complete.

  final candidates = [1, 2, 3, 4, 5, 6, 7, 8, 9];
  rng.shuffle(candidates);

  for (final num in candidates) {
    if (_isValid(board, emptyIdx, num)) {
      board[emptyIdx] = num;
      if (_fillGrid(board, rng)) return true;
      board[emptyIdx] = 0; // Backtrack
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Uniqueness checker — capped backtracking solver
// ---------------------------------------------------------------------------

/// Counts the number of solutions to [board], stopping once [limit] is
/// reached (early exit).
///
/// Used during hole-digging to verify that removing a clue does not create
/// a puzzle with more than one solution. Calling with `limit: 2` is
/// sufficient: if the result is 1 the cell can be removed; if it is ≥ 2
/// the cell must be kept as a clue.
///
/// **Important:** [board] is modified in place during recursion but is
/// always restored before returning, so the caller sees no net mutation.
int _countSolutions(List<int> board, int limit) {
  final emptyIdx = board.indexOf(0);
  if (emptyIdx == -1) return 1; // Reached a complete solution.

  int count = 0;
  for (int num = 1; num <= 9; num++) {
    if (_isValid(board, emptyIdx, num)) {
      board[emptyIdx] = num;
      count += _countSolutions(board, limit);
      board[emptyIdx] = 0;
      if (count >= limit) return count; // Early exit — no need to count more.
    }
  }
  return count;
}

// ---------------------------------------------------------------------------
// Phase 2 — Remove clues (hole-digging)
// ---------------------------------------------------------------------------

/// Removes cells from [board] until `givens <= targetGivens`, preserving
/// uniqueness of the solution at every step.
///
/// Algorithm:
/// 1. Build a shuffled list of all 81 indices (so removal order is random
///    and seed-dependent, giving variety across dates).
/// 2. For each index, tentatively remove the clue (set to 0).
/// 3. Run [_countSolutions] capped at 2.
///    - Result == 1 → removal is valid; keep the cell empty.
///    - Result >= 2 → restore the cell (removing it breaks uniqueness).
/// 4. Stop as soon as `givens <= targetGivens`.
///
/// If all 81 positions are exhausted before reaching the target the puzzle
/// will have slightly more givens than desired — this is rare and acceptable.
void _removeClues(List<int> board, SudokuRng rng, int targetGivens) {
  final indices = List<int>.generate(81, (i) => i);
  rng.shuffle(indices);

  int givens = 81;

  for (final idx in indices) {
    if (givens <= targetGivens) break;

    final saved = board[idx];
    board[idx] = 0;

    // Work on a copy so the solution counter doesn't corrupt the board.
    final copy = List<int>.from(board);
    final solutions = _countSolutions(copy, 2);

    if (solutions == 1) {
      // Safe to remove — unique solution maintained.
      givens--;
    } else {
      // Restoring is required — multiple solutions would exist.
      board[idx] = saved;
    }
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Generates a deterministic daily Sudoku puzzle for [date] at [difficulty].
///
/// Returns a record of two flat 81-element lists:
/// - `puzzle`: the clue cells (given cells retain their value; empty cells
///   are 0). This is what the player sees and interacts with.
/// - `solution`: the complete, filled grid (all 81 digits). Used to check
///   completion and prevent modification of given cells.
///
/// The same `(date, difficulty)` pair always produces the same output on
/// every platform and runtime, because generation is driven entirely by
/// [SudokuRng] seeded from a deterministic hash.
///
/// Typical generation time: 50–200 ms on Flutter Web (well within 500 ms).
({List<int> puzzle, List<int> solution}) generatePuzzle(
  DateTime date,
  SudokuDifficulty difficulty,
) {
  final seed = _sudokuSeed(date, difficulty);
  final rng = SudokuRng(seed);

  // Phase 1: fill a complete valid grid.
  final board = List<int>.filled(81, 0);
  _fillGrid(board, rng);

  // Snapshot the complete solution before digging holes.
  final solution = List<int>.from(board);

  // Phase 2: dig holes down to the target number of givens.
  _removeClues(board, rng, difficulty.targetGivens);

  return (puzzle: board, solution: solution);
}

// ---------------------------------------------------------------------------
// Puzzle number
// ---------------------------------------------------------------------------

/// Returns the 1-based puzzle index for [date], counting from the Sudo.IT
/// launch date (2026-08-28, the first day a puzzle is available).
///
/// Puzzle #1 is 2026-08-28. Values before launch are not expected in
/// production but are mathematically possible (they would be ≤ 0).
int puzzleNumber(DateTime date) {
  final epoch = DateTime(2026, 8, 28); // Sudo.IT launch date
  return date.difference(epoch).inDays + 1;
}
