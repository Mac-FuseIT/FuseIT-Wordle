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
// Grid generation — pattern-based
// ---------------------------------------------------------------------------

/// Signature for a pattern generator function.
///
/// Each pattern picks its own colors from [rng] and returns a filled 5×5 grid.
typedef PatternFn = List<List<String>> Function(SeededRng rng);

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

/// All available pattern generators.
///
/// Each entry is a closure that picks colors from [rng] and fills the grid
/// according to a simple geometric rule. The patterns are ordered by
/// complexity so they are easy to reason about.
final List<PatternFn> _patterns = [
  // 1. Checkerboard — (x + y) % 2 determines color.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => (x + y) % 2 == 0 ? c[0] : c[1]);
  },
  // 2. Vertical stripes — alternates on x.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => x % 2 == 0 ? c[0] : c[1]);
  },
  // 3. Horizontal stripes — alternates on y.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => y % 2 == 0 ? c[0] : c[1]);
  },
  // 4. Main diagonal — cells where x == y get color A.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => x == y ? c[0] : c[1]);
  },
  // 5. Anti-diagonal — cells where x + y == 4 get color A.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => x + y == 4 ? c[0] : c[1]);
  },
  // 6. Border — outer edge cells get color A, inner cells get color B.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid(
      (x, y) => (x == 0 || x == 4 || y == 0 || y == 4) ? c[0] : c[1],
    );
  },
  // 7. Quadrants — top-left triangle (x + y < 4) → A, bottom-right → B,
  //    the diagonal itself is also color A.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => x + y <= 4 ? c[0] : c[1]);
  },
  // 8. Cross — center column (x==2) or center row (y==2) → A, rest → B.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => (x == 2 || y == 2) ? c[0] : c[1]);
  },
  // 9. Three vertical stripes — left two cols, middle col, right two cols.
  (rng) {
    final c = _pickColors(rng, 3);
    return _makeGrid((x, y) => x < 2 ? c[0] : (x > 2 ? c[2] : c[1]));
  },
  // 10. Three horizontal stripes — top two rows, middle row, bottom two rows.
  (rng) {
    final c = _pickColors(rng, 3);
    return _makeGrid((x, y) => y < 2 ? c[0] : (y > 2 ? c[2] : c[1]));
  },
  // 11. Modulo-3 checkerboard — (x + y) % 3 cycles through three colors.
  (rng) {
    final c = _pickColors(rng, 3);
    return _makeGrid((x, y) => c[(x + y) % 3]);
  },
  // 12. Diamond — Manhattan distance from center ≤ 2 → A, else B.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid(
      (x, y) => (x - 2).abs() + (y - 2).abs() <= 2 ? c[0] : c[1],
    );
  },
  // 13. X pattern — both diagonals combined → A, rest → B.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => (x == y || x + y == 4) ? c[0] : c[1]);
  },
  // 14. Column cycling — x % 3 selects among three colors.
  (rng) {
    final c = _pickColors(rng, 3);
    return _makeGrid((x, y) => c[x % 3]);
  },
  // 15. Row cycling — y % 3 selects among three colors.
  (rng) {
    final c = _pickColors(rng, 3);
    return _makeGrid((x, y) => c[y % 3]);
  },
  // 16. Inner diamond + border (3 colors):
  //     outer border → A, tight center diamond → C, rest → B.
  (rng) {
    final c = _pickColors(rng, 3);
    return _makeGrid((x, y) {
      if (x == 0 || x == 4 || y == 0 || y == 4) return c[0];
      if ((x - 2).abs() + (y - 2).abs() <= 1) return c[2];
      return c[1];
    });
  },
  // 17. Thick vertical stripes (2 columns wide).
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => (x ~/ 2) % 2 == 0 ? c[0] : c[1]);
  },
  // 18. Thick horizontal stripes (2 rows tall).
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => (y ~/ 2) % 2 == 0 ? c[0] : c[1]);
  },
  // 19. Four corners — corner cells → A, everything else → B.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid(
      (x, y) =>
          ((x == 0 || x == 4) && (y == 0 || y == 4)) ? c[0] : c[1],
    );
  },
  // 20. Top-heavy split — top 3 rows → A, bottom 2 rows → B.
  (rng) {
    final c = _pickColors(rng, 2);
    return _makeGrid((x, y) => y < 3 ? c[0] : c[1]);
  },
];

/// Generates the target 5×5 grid for [date].
///
/// Algorithm:
/// 1. Derive an integer seed from the date string.
/// 2. Pick one of the [_patterns] deterministically via the seeded RNG.
/// 3. The chosen pattern picks its own colors from the same RNG and fills
///    the grid according to a simple geometric rule.
///
/// Every puzzle therefore has an elegant one- or two-line solution using
/// loops and a condition, rather than a fully random arrangement.
///
/// The result is a row-major list: `grid[row][col]`, where both indices are
/// in the range 0–4, and every value is a lowercase color name from [allColors].
List<List<String>> generateTarget(DateTime date) {
  final rng = SeededRng(_dateToSeed(date));
  final patternIndex = rng.nextInt(_patterns.length);
  return _patterns[patternIndex](rng);
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
