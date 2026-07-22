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
