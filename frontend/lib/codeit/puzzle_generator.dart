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
// Difficulty
// ---------------------------------------------------------------------------

/// Difficulty levels for Code.IT puzzles.
///
/// Each level controls how many distinct colors appear in the target grid:
/// - [easy]: 2 colors — straightforward binary patterns.
/// - [mild]: 3 colors — requires an extra condition or variable.
/// - [challenging]: 4 colors — needs more nuanced logic to reproduce.
enum Difficulty { easy, mild, challenging }

// ---------------------------------------------------------------------------
// Grid generation — pattern-based
// ---------------------------------------------------------------------------

/// Picks [count] distinct colors from [allColors] using a Fisher-Yates shuffle
/// driven by [rng].
List<String> _pickColors(SeededRng rng, int count) {
  final shuffled = List<String>.from(allColors);
  for (int i = shuffled.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }
  return shuffled.sublist(0, count);
}

/// Builds a 5×5 grid by calling [cellFn] for every (x, y) position.
///
/// x is the column index (0–4, left→right).
/// y is the row index (0–4, top→bottom).
List<List<String>> _makeGrid(String Function(int x, int y) cellFn) {
  return List.generate(5, (y) => List.generate(5, (x) => cellFn(x, y)));
}

/// 20 geometric patterns, each expressed as a mapping from (x, y) to a
/// [colors] index.  Patterns are designed to remain sensible regardless of
/// whether [colors] has 2, 3, or 4 entries:
///
/// - Patterns 0–7  are fundamentally binary but gracefully use extra colors
///   when [n] > 2 (e.g. modulo index keeps cycling).
/// - Patterns 8–10 stripe / cycle in 3 parts, using `n` for the modulus.
/// - Patterns 11–19 mix two-region and multi-region logic; indices are
///   clamped so they are always within [colors] bounds.
List<List<String>> _generateWithColors(
  SeededRng rng,
  int patternIndex,
  List<String> colors,
) {
  final n = colors.length;
  switch (patternIndex % 20) {
    // 0. Checkerboard — (x + y) % 2 alternates.
    case 0:
      return _makeGrid((x, y) => colors[(x + y) % 2 == 0 ? 0 : 1]);
    // 1. Vertical stripes — alternates on x.
    case 1:
      return _makeGrid((x, y) => colors[x % 2]);
    // 2. Horizontal stripes — alternates on y.
    case 2:
      return _makeGrid((x, y) => colors[y % 2]);
    // 3. Main diagonal — cells where x == y get color 0.
    case 3:
      return _makeGrid((x, y) => colors[x == y ? 0 : 1]);
    // 4. Anti-diagonal — cells where x + y == 4 get color 0.
    case 4:
      return _makeGrid((x, y) => colors[(x + y == 4) ? 0 : 1]);
    // 5. Border — outer edge → color 0, interior → color 1.
    case 5:
      return _makeGrid(
        (x, y) =>
            colors[(x == 0 || x == 4 || y == 0 || y == 4) ? 0 : 1],
      );
    // 6. Triangle split — x + y <= 4 → color 0, rest → color 1.
    case 6:
      return _makeGrid((x, y) => colors[x + y <= 4 ? 0 : 1]);
    // 7. Cross — center column or row → color 0, rest → color 1.
    case 7:
      return _makeGrid(
        (x, y) => colors[(x == 2 || y == 2) ? 0 : 1],
      );
    // 8. Three vertical stripes — left/middle/right using n as modulus.
    case 8:
      return _makeGrid(
        (x, y) => colors[x < 2 ? 0 : (x > 2 ? (n > 2 ? 2 : 1) : 1)],
      );
    // 9. Three horizontal stripes — top/middle/bottom using n.
    case 9:
      return _makeGrid(
        (x, y) => colors[y < 2 ? 0 : (y > 2 ? (n > 2 ? 2 : 1) : 1)],
      );
    // 10. Modulo cycling — (x + y) % n cycles through all colors.
    case 10:
      return _makeGrid((x, y) => colors[(x + y) % n]);
    // 11. Diamond — Manhattan distance from center ≤ 2 → color 0, else 1.
    case 11:
      return _makeGrid(
        (x, y) =>
            colors[(x - 2).abs() + (y - 2).abs() <= 2 ? 0 : 1],
      );
    // 12. X pattern — both diagonals → color 0, rest → color 1.
    case 12:
      return _makeGrid(
        (x, y) => colors[(x == y || x + y == 4) ? 0 : 1],
      );
    // 13. Column cycling — x % n selects color.
    case 13:
      return _makeGrid((x, y) => colors[x % n]);
    // 14. Row cycling — y % n selects color.
    case 14:
      return _makeGrid((x, y) => colors[y % n]);
    // 15. Inner diamond + border (uses up to 3 colors):
    //     outer border → color 0, tight center → color 2 (or 0), rest → color 1.
    case 15:
      return _makeGrid((x, y) {
        if (x == 0 || x == 4 || y == 0 || y == 4) return colors[0];
        if ((x - 2).abs() + (y - 2).abs() <= 1) return colors[n > 2 ? 2 : 0];
        return colors[1];
      });
    // 16. Thick vertical stripes (2 columns wide).
    case 16:
      return _makeGrid((x, y) => colors[(x ~/ 2) % 2]);
    // 17. Thick horizontal stripes (2 rows tall).
    case 17:
      return _makeGrid((x, y) => colors[(y ~/ 2) % 2]);
    // 18. Four corners only → color 0, everything else → color 1.
    case 18:
      return _makeGrid(
        (x, y) =>
            colors[((x == 0 || x == 4) && (y == 0 || y == 4)) ? 0 : 1],
      );
    // 19. Top-heavy split — top 3 rows → color 0, bottom 2 rows → color 1.
    case 19:
      return _makeGrid((x, y) => colors[y < 3 ? 0 : 1]);
    default:
      return _makeGrid((x, y) => colors[0]);
  }
}

/// Generates the target 5×5 grid for [date] at the given [difficulty].
///
/// Algorithm:
/// 1. Build a date string with a difficulty suffix so each level gets a
///    distinct seed (and therefore a distinct grid) for the same day.
/// 2. Hash the string into a 31-bit seed for [SeededRng].
/// 3. Pick [numColors] distinct colors from [allColors] via [_pickColors].
/// 4. Pick one of 20 geometric patterns deterministically.
/// 5. Fill the 5×5 grid using [_generateWithColors], which maps (x, y) to
///    a color index — always within the bounds of the chosen palette.
///
/// Color counts by difficulty:
/// - [Difficulty.easy]        → 2 colors
/// - [Difficulty.mild]        → 3 colors
/// - [Difficulty.challenging] → 4 colors
///
/// The result is row-major: `grid[row][col]`, indices 0–4, values are
/// lowercase color names from [allColors].
List<List<String>> generateTarget(
  DateTime date, [
  Difficulty difficulty = Difficulty.easy,
]) {
  // Append a suffix so Easy/Mild/Challenging each get a different seed.
  final suffix = switch (difficulty) {
    Difficulty.easy => '-easy',
    Difficulty.mild => '-mild',
    Difficulty.challenging => '-hard',
  };
  final dateStr =
      '${date.year}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}'
      '$suffix';
  int hash = 0;
  for (int i = 0; i < dateStr.length; i++) {
    hash = (hash * 31 + dateStr.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  final rng = SeededRng(hash);

  final numColors = switch (difficulty) {
    Difficulty.easy => 2,
    Difficulty.mild => 3,
    Difficulty.challenging => 4,
  };

  final colors = _pickColors(rng, numColors);
  final patternIndex = rng.nextInt(20);
  return _generateWithColors(rng, patternIndex, colors);
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
