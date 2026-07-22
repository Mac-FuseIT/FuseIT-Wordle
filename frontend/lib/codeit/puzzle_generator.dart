/// Deterministic puzzle generation for Code.IT.
///
/// The target grid is derived entirely from the current date — every client
/// running the same date produces the identical 5×5 grid, with no backend
/// involvement required for gameplay.
library codeit.puzzle_generator;

// ---------------------------------------------------------------------------
// Seeded RNG
// ---------------------------------------------------------------------------

/// Seeded Linear Congruential Generator for deterministic puzzles.
///
/// Uses the classic glibc LCG parameters so the sequence is well-understood
/// and identical across all platforms (Dart VM, Flutter web, etc.).
class SeededRng {
  int _state;

  SeededRng(this._state);

  /// Returns a non-negative pseudorandom integer in [0, max).
  ///
  /// Uses the upper 15 bits of the LCG state (`_state >> 16`) rather than the
  /// raw low bits. Low bits of a standard LCG have notoriously short periods
  /// (bit 0 alternates every step), which causes uniform-looking grids when
  /// the palette size is a power of two. Shifting right by 16 discards those
  /// weak low bits and uses the higher-quality upper portion of the state.
  int nextInt(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return (_state >> 16) % max; // Use upper bits for better distribution
  }
}

// ---------------------------------------------------------------------------
// Seed derivation
// ---------------------------------------------------------------------------

/// Converts a [date] to a numeric seed by hashing its ISO-style date string.
///
/// Example: `DateTime(2026, 7, 22)` → hash of `"2026-07-22"`.
/// The 0x7FFFFFFF mask keeps the value positive and within 31-bit range,
/// matching the LCG mask in [SeededRng].
int _dateToSeed(DateTime date) {
  final dateStr =
      '${date.year}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  int hash = 0;
  for (int i = 0; i < dateStr.length; i++) {
    hash = (hash * 31 + dateStr.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return hash;
}

// ---------------------------------------------------------------------------
// Color palette
// ---------------------------------------------------------------------------

/// Full set of colors available for puzzle palettes.
///
/// Order matters for the shuffle — do not reorder without bumping the epoch,
/// as it would change every historical puzzle.
const List<String> allColors = [
  'black',
  'red',
  'blue',
  'yellow',
  'green',
  'white',
  'purple',
  'orange',
];

// ---------------------------------------------------------------------------
// Grid generation
// ---------------------------------------------------------------------------

/// Generates the target 5×5 grid for [date].
///
/// Algorithm:
/// 1. Derive an integer seed from the date string.
/// 2. Pick 2–4 colors via Fisher-Yates shuffle of [allColors].
/// 3. Fill every cell of the grid by randomly sampling the chosen palette.
///
/// The result is a row-major list: `grid[row][col]`, where both indices are
/// in the range 0–4, and every value is a lowercase color name from [allColors].
List<List<String>> generateTarget(DateTime date) {
  final rng = SeededRng(_dateToSeed(date));

  // Pick 2–4 colors for today's puzzle (nextInt(3) → 0, 1, or 2 → +2 = 2, 3, 4).
  final numColors = 2 + rng.nextInt(3);

  // Fisher-Yates shuffle to randomise the color list, then take the first N.
  final shuffled = List<String>.from(allColors);
  for (int i = shuffled.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }
  final palette = shuffled.sublist(0, numColors);

  // Fill the 5×5 grid by sampling the palette with the seeded RNG.
  return List.generate(
    5,
    (row) => List.generate(5, (_) => palette[rng.nextInt(numColors)]),
  );
}

// ---------------------------------------------------------------------------
// Puzzle number
// ---------------------------------------------------------------------------

/// Returns the 1-based puzzle index for [date], counting from the launch date.
///
/// Puzzle #1 is 2026-07-22 (launch day). Negative values are possible for
/// dates before launch but are not expected in production.
int puzzleNumber(DateTime date) {
  final epoch = DateTime(2026, 7, 22); // Code.IT launch date
  return date.difference(epoch).inDays + 1;
}
