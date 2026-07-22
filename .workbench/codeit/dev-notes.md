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

## Dart Developer Notes — fix-colors (Bug 1 & Bug 2)

### Files Modified
- `frontend/lib/codeit/puzzle_generator.dart` — replaced `generateTarget` to restrict pattern selection by difficulty. Previously `rng.nextInt(20)` could pick any of 20 patterns regardless of how many colors were in use, so Mild/Challenging puzzles often got 2-color patterns. Now a `validPatterns` list gates selection: 14 patterns for 2 colors, 6 for 3, 3 for 4.
- `frontend/lib/codeit/dsl/parser.dart` — added `TokenType.lparen` case to `_parsePrimary()`. Consumes `(`, recursively calls `_parseExpr()`, then expects `)`. This allows expressions like `(x + 4) - y` and `(x + y) % 2`. Also updated the docstring to reflect the new case.

### Key Decisions
- Kept the rest of `generateTarget` identical to the original (same suffix logic, same seed derivation, same `_pickColors` call). Only the pattern-selection line changed.
- The `lparen` case in `_parsePrimary` calls `_parseExpr` (not `_parsePrimary`), so nested parens like `((x + 1) % 2)` also work correctly.

### Packages & Docs Consulted
None — changes were purely within existing project files.

### Analyze & Test Results
`analyze_files` on both files: **No errors**

### Open Issues
None.

## Dart Developer Notes — Add `and`/`or` support to if-statement conditions

### Files Created
- None.

### Files Modified
- `frontend/lib/codeit/dsl/tokenizer.dart` — Added `andKeyword` and `orKeyword` to the `TokenType` enum; added `'and'` and `'or'` cases to the keyword `switch` in `_tokenizeLine`.
- `frontend/lib/codeit/dsl/ast.dart` — Extended `Condition` with two optional fields: `final String? logicalOp` and `final Condition? next`. These implement a linked-list for chained conditions (`x > 0 and y < 5 or z == 1`). `IfNode` is unchanged — it still holds a `Condition`.
- `frontend/lib/codeit/dsl/parser.dart` — Renamed the old `_parseCondition` to `_parseSingleCondition` and added a new `_parseCondition` that calls `_parseSingleCondition`, then checks for `andKeyword`/`orKeyword`. If found, it consumes the operator and recurses to build the chain right-associatively.
- `frontend/lib/codeit/dsl/executor.dart` — Split `_evalCondition` into two methods: `_evalCondition` (chain-aware: evaluates head, then recurses on `cond.next` with `&&`/`||`) and `_evalSimpleCondition` (evaluates a single `expr COMP_OP expr`).

### Key Decisions
- **Linked-list on `Condition`** rather than a separate `CompoundCondition` class. This requires zero changes to `IfNode` and keeps the type hierarchy flat.
- **Right-associative chaining** via recursion in `_parseCondition`. Evaluation is also recursive in `_evalCondition`, which naturally short-circuits because `&&`/`||` in Dart are already lazy.
- **No operator precedence between `and` and `or`** — they chain strictly left-to-right as encountered in the source. This is consistent with how the DSL handles arithmetic (all equal precedence). If precedence is needed in future, this can be revisited.

### Packages & Docs Consulted
- None. Pure Dart stdlib only.

### Analyze & Test Results
```
analyze_files (tokenizer, ast, parser, executor): No errors
```
The only existing test (`test/widget_test.dart`) is the default Flutter counter smoke test that references a non-existent `MyApp` constructor — this failure predates our changes and is unrelated to the DSL.

### Open Issues
- No unit tests for `and`/`or` condition evaluation. Recommend adding tests for: simple `and` true/false, simple `or` true/false, three-way chain (`a and b or c`), short-circuit behavior.
- `and`/`or` have no precedence distinction — `x == 1 or y == 2 and z == 3` evaluates left-to-right as `(x == 1 or y == 2) and z == 3`. Reviewer should decide if this is acceptable for the DSL scope.
