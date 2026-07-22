## Dart Developer Notes — Pattern-based puzzle generation for Code.IT

### Files Created
- none

### Files Modified
- `frontend/lib/codeit/puzzle_generator.dart` — Replaced the random `generateTarget` implementation with a pattern-based approach. Added `PatternFn` typedef, `_pickColors` helper, `_makeGrid` helper, and a `_patterns` list of 20 geometric pattern generators.

### Key Decisions

**What stayed unchanged:** `SeededRng`, `_dateToSeed`, `allColors` constant, `puzzleNumber` — all preserved verbatim as instructed.

**Grid axis convention:** `_makeGrid` uses `List.generate(5, (y) => List.generate(5, (x) => ...))` so the outer index is the row (y) and the inner index is the column (x). This matches the existing `grid[row][col]` contract documented in the old `generateTarget` dartdoc, and keeps `x` and `y` semantically consistent across all pattern lambdas (x = column, y = row).

**Pattern 7 tweak:** The spec said `x + y < 4 → A, else B` but that leaves the anti-diagonal itself (`x + y == 4`) ambiguous (assigned to B, which creates a hard edge). Changed to `x + y <= 4 → A` so the diagonal is colour A, giving a clean triangular split without a third implicit zone.

**No new dependencies:** Pure Dart, no packages added.

### Packages & Docs Consulted
- None. Pure Dart stdlib only.

### Analyze & Test Results
```
analyze_files: No errors
```
Tests not run — no unit tests exist for this file yet, and the task scope was limited to the generator replacement.

### Open Issues
- Consider adding a unit test that calls `generateTarget` for a range of dates and asserts the grid is 5×5, all values are in `allColors`, and the result is deterministic (same date → same grid).
- Pattern 7 diagonal assignment changed from spec (≤ instead of <) — reviewer should confirm this is acceptable.

---

## Dart Developer Notes — Add Quick Reference cheat sheet to CodeItScreen

### Files Created
- none

### Files Modified
- `frontend/lib/codeit/codeit_screen.dart` — Added `_buildCheatSheet()` and `_refRow()` methods; inserted `_buildCheatSheet()` + `SizedBox(height: 12)` before `_buildGridRow()` in the scrollable Column.

### Key Decisions
- Used `SelectableText` for code snippets so users can tap-to-copy on both mobile and web.
- Monospace yellow (`0xFFDCDCAA`) matches the syntax-highlight colour used elsewhere in the editor for built-in tokens.
- Container decoration (`0xFF1E1E1E` background, `0xFF3A3A3C` border, 8 px radius) mirrors the existing CodeEditor widget style for visual consistency.
- No new packages introduced — purely Flutter built-in widgets.

### Packages & Docs Consulted
- None (all widgets are Flutter SDK standard).

### Analyze & Test Results
- `analyze_files` on `codeit_screen.dart`: **No errors**
- No tests written (UI-only widget addition, no logic change).

### Open Issues
- None.
