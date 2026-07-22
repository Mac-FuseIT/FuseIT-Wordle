# Dev Notes — Code.IT DSL Engine: errors.dart & ast.dart

## Dart Developer Notes — Create DSL error and AST node classes

### Files Created
- `frontend/lib/codeit/dsl/errors.dart` — `DslError` exception class with optional line number, used by parser and executor to surface errors with location info
- `frontend/lib/codeit/dsl/ast.dart` — All AST node classes: `AstNode` (abstract base), `ProgramNode`, `ForNode`, `IfNode`, `FuncCallNode`, `NumberLiteral`, `StringLiteral`, `VariableRef`, `BinaryExpr`, and the `Condition` value class

### Files Modified
- None

### Key Decisions
- Implemented files exactly as specified — no deviations
- `Condition` is a plain class (not extending `AstNode`) as specified, since conditions are not standalone statements but are embedded within `IfNode`
- Files are placed under `frontend/lib/codeit/dsl/` to match the expected DSL engine package structure

### Packages & Docs Consulted
- None — pure Dart classes with no third-party dependencies

### Analyze & Test Results
- `analyze_files` on both files: **No errors**
- No tests exist yet for these classes (parser/executor will exercise them)

### Open Issues
- None — files are clean and ready for the parser/executor to build on top of

## Dart Developer Notes — Wire Code.IT into main menu and routing

### Files Created
- None

### Files Modified
- `frontend/lib/main.dart` — Added `codeItGame` to `AppView` enum; added `import 'codeit/codeit_screen.dart'`; added `onCodeIT` callback to `MainMenuScreen` instantiation; added `AppView.codeItGame` routing case pointing to `CodeItScreen`
- `frontend/lib/screens/main_menu_screen.dart` — Added `final VoidCallback onCodeIT` field and required constructor param; added Code.IT `_GameCard` after Gamble.IT in the Lounge row

### Key Decisions
- `codeItGame` placed before `profile` in the enum and routing switch to keep profile last (consistent with existing ordering)
- Code.IT card uses `theme.present` colour and `Icons.code` icon as specified
- The Lounge row now has three cards: Chess.IT, Gamble.IT, Code.IT

### Packages & Docs Consulted
- None — only Flutter framework APIs already in use by the project

### Analyze & Test Results
- `analyze_files` on `main.dart` and `main_menu_screen.dart`: **No errors**

### Open Issues
- `CodeItScreen` import will produce an analyzer warning until `frontend/lib/codeit/codeit_screen.dart` is created by a subsequent task
