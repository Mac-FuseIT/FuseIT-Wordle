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
