## Dart Developer Notes — DSL Tokenizer

### Files Created
- `frontend/lib/codeit/dsl/tokenizer.dart` — DSL tokenizer: converts source string to `List<Token>` with INDENT/DEDENT tracking, line numbers, and keyword recognition.

### Files Modified
- None.

### Key Decisions
- Used Dart 3 exhaustive `switch` expressions (no `break` needed) for the keyword and operator dispatch — cleaner than the `case x: ...; break` pattern in the spec.
- Extracted `_leadingSpaces()` helper to count leading spaces after trimRight, avoiding a redundant `trimLeft().length` subtraction that is harder to read.
- Kept `_isDigit`, `_isAlpha`, `_isAlphaNum` as top-level functions (not methods) — consistent with the spec and idiomatic for small predicate helpers in Dart library files.
- `Token` constructor marked `const` — instances created at runtime won't be const, but the constructor allows const usage in tests.

### Packages & Docs Consulted
- None. No third-party packages used or needed.

### Analyze & Test Results
- `analyze_files` on `tokenizer.dart` and `errors.dart`: **No errors**.
- No existing tests for this module. Tests to be written by a subsequent agent.

### Open Issues
- Token tests not yet written — a test file for `tokenizer.dart` should be created under `frontend/test/codeit/dsl/tokenizer_test.dart`.
- `parser.dart` and `executor.dart` are next in the pipeline and will `import 'tokenizer.dart'` for `Token`/`TokenType`.

---

## Dart Developer Notes — DSL Parser

### Files Created
- `frontend/lib/codeit/dsl/parser.dart` — Recursive descent parser: consumes `List<Token>` → `ProgramNode` AST. Exposes a top-level `parse()` function.

### Files Modified
- None.

### Key Decisions
- Used Dart 3 exhaustive `switch` in `_parseStatement()` for cleaner dispatch over `TokenType`.
- `_nestingDepth` guard fires *before* parsing the nested body so the `DslError` line number points at the offending `for` keyword, not somewhere inside the body.
- `_peek()` from the spec skeleton was dropped — it was unused (`_current` getter covers all look-ahead needs).
- All binary operators (`%`, `+`, `-`) share equal precedence and are left-associative. This matches the grammar in the spec and is sufficient for the DSL's use-cases (`x % 2`, `x + 1`, etc.).

### Packages & Docs Consulted
- None. No third-party packages used or needed.

### Analyze & Test Results
- `analyze_files` on `parser.dart`, `tokenizer.dart`, `ast.dart`, `errors.dart`: **No errors**.
- No parser-specific tests written yet — test file should be created at `frontend/test/codeit/dsl/parser_test.dart`.

### Open Issues
- Parser tests not yet written.
- `executor.dart` is the next stage in the pipeline.

---

## Dart Developer Notes — Puzzle Generator

### Files Created
- `frontend/lib/codeit/puzzle_generator.dart` — Deterministic 5×5 grid generator for Code.IT. Exposes `SeededRng`, `allColors`, `generateTarget(DateTime)`, and `puzzleNumber(DateTime)`.

### Files Modified
- None.

### Key Decisions
- Implemented exactly as specified: LCG parameters `(1103515245, 12345)` with `& 0x7FFFFFFF` mask, date string format `"YYYY-MM-DD"` hashed with multiplier 31.
- Renamed the row dimension parameter from `x` to `row` in `List.generate` to avoid shadowing the `x` loop variable from the spec — cleaner and less confusing on review.
- Added a `library` directive (`library codeit.puzzle_generator`) for clarity in a multi-file package.
- Epoch remains `DateTime(2026, 7, 22)` as specified.

### Packages & Docs Consulted
- None. Pure Dart, no third-party packages.

### Analyze & Test Results
- `analyze_files` on `puzzle_generator.dart`: **No errors**.
- No unit tests written yet — a test file should be created at `frontend/test/codeit/puzzle_generator_test.dart` verifying seed stability, palette size, and grid dimensions.

### Open Issues
- Unit tests for `generateTarget` and `puzzleNumber` not yet written.

---

## Dart Developer Notes — DSL Executor

### Files Created
- `frontend/lib/codeit/dsl/executor.dart` — Walks the AST produced by the parser, maintains a flat variable scope (`Map<String, int>`), and writes colors into a 5×5 `List<List<String>>` grid. Exposes `ExecutionResult` and `DslExecutor`.

### Files Modified
- None.

### Key Decisions
- Matched the spec exactly: `maxSteps = 10000`, step counter increments once per statement (not per loop iteration), `range(negative)` returns without error.
- Used Dart 3 `switch` with `case` labels (no `break`) in `_execFunc` and `_evalExpr` — same style as tokenizer and parser.
- `_execBlock` is the single choke-point for the step counter and limit check — avoids duplicating the guard in each branch.
- `_vars.remove(node.variable)` after a for loop restores the outer scope correctly for nested loops with the same variable name (inner `x` doesn't leak to outer `x`).
- Friendly typo suggestions in `_execFunc` default case: checks `.contains('pixel')` / `.contains('fill')` to catch common variations.
- `e.toString()` used in `execute()` catch — `DslError.toString()` already prepends "Line N:" when a line is present, matching the display format in the spec.

### Packages & Docs Consulted
- None. No third-party packages used or needed.

### Analyze & Test Results
- `analyze_files` on `executor.dart`: **No errors**.
- No executor-specific tests written yet — test file should be created at `frontend/test/codeit/dsl/executor_test.dart`.

### Open Issues
- Executor tests not yet written.
- All four DSL files (`tokenizer.dart`, `parser.dart`, `ast.dart`, `executor.dart`) are now in place. Next step is wiring them together in `codeit_screen.dart` or writing integration tests.

## Dart Developer Notes — Code.IT game screen and widgets

### Files Created
- `frontend/lib/codeit/widgets/pixel_grid.dart` — 5×5 colored grid widget with optional green/red match overlay per cell
- `frontend/lib/codeit/widgets/code_editor.dart` — monospace multi-line TextField; intercepts Tab → 4 spaces via KeyboardListener
- `frontend/lib/codeit/widgets/console_output.dart` — styled output panel (info/success/error states with matching border tint)
- `frontend/lib/codeit/codeit_screen.dart` — main StatefulWidget composing all three widgets; handles tokenize → parse → execute pipeline, match comparison, SharedPreferences persistence of code per day

### Files Modified
- none

### Key Decisions
- **`withValues(alpha:)` instead of deprecated `withOpacity`** — used throughout to avoid analyzer deprecation warnings
- **`FocusNode(skipTraversal: true, canRequestFocus: false)`** on the `KeyboardListener` wrapping the editor — prevents it from capturing focus and fighting the inner `TextField`; Tab handling is event-based so this works correctly
- **`WidgetsBinding.instance.addPostFrameCallback`** for `_loadSavedCode` — defers the `TextEditingController` write until after the widget is mounted, avoiding any "controller used before build" edge cases
- **Column-major grid indexing (`grid[x][y]`)** — matches the spec and executor convention; `PixelGrid` iterates `y` in the outer loop and `x` in the inner to render rows correctly
- **`_puzzleNum` and `_target` as `late final`** — computed once in `initState` from `DateTime.now()` so they never change during the session

### Packages & Docs Consulted
- `shared_preferences` — already in pubspec; used for daily code persistence (key `codeit_code_YYYY-M-D`)
- Dart MCP `analyze_files` — confirmed zero errors across all 4 files

### Analyze & Test Results
```
No errors
```
(analyzed: codeit_screen.dart, pixel_grid.dart, code_editor.dart, console_output.dart)

### Open Issues
- `CodeItScreen` is not yet wired into `main.dart` / `main_menu_screen.dart` — that integration is a separate task per the spec
- No celebration animation (confetti / glow) — spec marks this as a follow-up (task 11)
- Optional backend completion tracking (`codeit_service.dart`, POST /api/codeit/complete) not implemented — separate task per spec

## Dart Developer Notes — Fix RNG + Syntax Highlighting

### Files Modified
- `frontend/lib/codeit/puzzle_generator.dart` — Changed `nextInt` to use `(_state >> 16) % max` instead of `_state % max`. Low bits of a standard LCG have very short periods (bit 0 strictly alternates every step); shifting right by 16 discards the weak low bits and uses the upper, higher-quality portion of the 31-bit state. This prevents the grid-fill loop from sampling only alternating colours when the palette size is 2.
- `frontend/lib/codeit/widgets/code_editor.dart` — Converted from a plain `StatelessWidget` wrapping a plain `TextField` to a `StatefulWidget` with a private `_HighlightController` (a `TextEditingController` subclass). The controller overrides `buildTextSpan` to tokenise the source text character-by-character and emit coloured `TextSpan` children. Bidirectional sync listeners keep the parent's external controller and the internal highlight controller in step. `KeyboardListener` replaced with `Focus` + `onKeyEvent` (which returns a `KeyEventResult`) to properly consume Tab events.

### Key Decisions
- **Upper bits for LCG**: `>> 16` discards the 16 weak low bits; the remaining 15 bits `(0..32767)` are then reduced with `% max`. This is the standard fix cited in Numerical Recipes and the glibc manual.
- **`_HighlightController` kept package-private** (prefixed `_`) — the parent widget only needs to see `CodeEditor` and a plain `TextEditingController`. No public API surface change.
- **Bidirectional sync via `addListener`**: The parent continues to use its own `TextEditingController` for `_run()` and `_saveCode()` — zero changes needed in `codeit_screen.dart`.
- **`Focus` over `KeyboardListener`**: `Focus.onKeyEvent` returns `KeyEventResult.handled` which stops the Tab event propagating to the focus system and changing focus. `KeyboardListener.onKeyEvent` has no return value so the event always keeps propagating — the old approach was already correct by luck (the `FocusNode(canRequestFocus: false)` trick), but `Focus` is the idiomatic solution.
- **Minimal token set**: Keywords `{for, in, range, if, else}` and builtins `{set_pixel, fill}` match exactly the DSL spec. Easy to extend by editing the two `static const` sets.

### Packages & Docs Consulted
- None. No third-party packages added or used.

### Analyze & Test Results
- `analyze_files` on `lib/codeit/puzzle_generator.dart` + `lib/codeit/widgets/code_editor.dart`: **No errors**
- `analyze_files` on `lib/codeit/` (full folder): **No errors**
- `run_tests`: pre-existing boilerplate `widget_test.dart` failure (`MyApp` not found) — unrelated to these changes; all other tests pass.

### Commits
- `fix: use upper LCG bits in nextInt for better randomness` (e68ffdd)
- `feat: add syntax highlighting to CodeEditor via _HighlightController` (4b197f4)

### Open Issues
- None from this task. The stale `widget_test.dart` should be replaced or deleted in a future chore task.
