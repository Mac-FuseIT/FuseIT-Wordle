# Task: Implement Pixel.IT — Daily Coding Puzzle

## User Request
Implement Pixel.IT, a daily coding puzzle game for Fuse Arcade. Players see a 5x5 target grid of colored cells and write Python-like DSL code to reproduce the pattern. All gameplay is client-side in Dart. Optional backend tracks completion status.

## Codebase Summary
- **Stack**: Flutter 3.x (Dart SDK ^3.11.0), Cloudflare Pages Functions (JS), D1 database. Dependencies: `http`, `shared_preferences`, `flutter_svg`, `web_socket_channel`, `chess`, `material_symbols_icons`.
- **Structure**: `frontend/lib/` contains game modules in subdirectories (`strands/`, `crossword/`, `solitaire/`, `blackjack/`, `chess/`, `pong/`, `invade/`). Each game has its own directory with screens, widgets, and services. Backend lives in `functions/api/<game>/` with JS handlers. Migrations in `migrations/`.
- **Conventions**:
  - Games get their own subdirectory: `frontend/lib/<game>/`
  - Screens are `StatefulWidget` with `AppTheme theme`, `VoidCallback onBack`, `String nickname`, `int userId` constructor params
  - Services use static methods, Bearer token auth via `SharedPreferences`
  - Navigation uses `AppView` enum + `switch` in `_AppShellState.build()`
  - Menu entries use `_GameCard` widget with `title`, `subtitle`, `icon`, `color`, `onTap`
  - Backend endpoints: simple JS functions in `functions/api/<game>/`, using `verifyToken` from `../../src/auth.js`
  - Migrations numbered sequentially: next is `0022`
- **Critical Findings**: None. No blockers. The project already has `shared_preferences` for localStorage (code persistence). No new dependencies needed.

## Relevant Files
- `frontend/lib/main.dart` — Add `AppView.codeItGame`, import, and switch case
- `frontend/lib/screens/main_menu_screen.dart` — Add `onCodeIT` callback and `_GameCard` to "The Lounge"
- `frontend/lib/models/app_theme.dart` — Reference only (use `theme.correct`, `theme.present`, `theme.background`, `theme.textColor`)
- `frontend/lib/services/api_service.dart` — Reference for auth header pattern
- `frontend/lib/solitaire/solitaire_service.dart` — Reference for service pattern
- `src/auth.js` — `verifyToken` for backend auth
- `src/db.js` — `jsonResponse` helper for backend

## Execution Plan

### Wave 1: DSL Engine (core language infrastructure)
| Sub-task | Agent | Details |
|----------|-------|---------|
| Create `frontend/lib/codeit/dsl/errors.dart` | dart-developer | Define `DslError` exception class with `message` and `line` fields |
| Create `frontend/lib/codeit/dsl/ast.dart` | dart-developer | Define all AST node classes: `ProgramNode`, `ForNode`, `IfNode`, `FuncCallNode`, `NumberLiteral`, `StringLiteral`, `VariableRef`, `BinaryExpr`, `Condition`. Follow spec exactly. |
| Create `frontend/lib/codeit/dsl/tokenizer.dart` | dart-developer | Implement tokenizer: line splitting, indentation tracking (INDENT/DEDENT tokens), keyword recognition (`for`, `in`, `range`, `if`, `else`), operators, identifiers, numbers, strings. Line numbers on every token. Normalize tabs → 4 spaces. |
| Create `frontend/lib/codeit/dsl/parser.dart` | dart-developer | Recursive descent parser. Consumes token stream, produces `ProgramNode`. Handles for loops, if/else, function calls, expressions with `%`, `+`, `-`, conditions with comparison ops. Error on first syntax issue with line number. Max nesting = 3. |
| Create `frontend/lib/codeit/dsl/executor.dart` | dart-developer | Walk AST, maintain variable scope, modify 5x5 grid. Enforce 10,000 step limit. Validate `set_pixel` bounds (0-4), color names, function arity. Return `ExecutionResult` with grid, error, steps. Friendly suggestions for typos. |
| Create `frontend/lib/codeit/puzzle_generator.dart` | dart-developer | Implement `SeededRng` (LCG), `_dateToSeed()`, `generateTarget()` (picks 2-4 colors, fills 5x5 grid), `puzzleNumber()` (epoch = 2026-07-22). All deterministic. |

### Wave 2: UI Widgets & Game Screen
| Sub-task | Agent | Details |
|----------|-------|---------|
| Create `frontend/lib/codeit/widgets/pixel_grid.dart` | dart-developer | 5x5 grid widget. Accepts `List<List<String>>` grid data and optional `List<List<bool>>?` matchOverlay. Cells are 40x40 (responsive), 1px `#333333` border, 2px radius, 2px gap. Color map from spec hex values. Green/red border overlay for match/mismatch after comparison. |
| Create `frontend/lib/codeit/widgets/code_editor.dart` | dart-developer | Multi-line `TextField` with `TextEditingController`. Monospace font, dark bg `#1E1E1E`, light text `#D4D4D4`. Min 8 visible lines, scrollable. Tab key inserts 4 spaces (via `KeyboardListener` or `Actions`). |
| Create `frontend/lib/codeit/widgets/console_output.dart` | dart-developer | Single/multi-line text. White for match count, green for success, red for errors. Accepts `String message` and `ConsoleType` enum (info/success/error). |
| Create `frontend/lib/codeit/codeit_screen.dart` | dart-developer | Main game screen `StatefulWidget`. Composes: AppBar (back, "Pixel.IT", puzzle number), GridRow (user canvas + target), CodeEditor, ButtonRow (Run + Reset), ConsoleOutput. State: `_attempts` counter, `_solved` bool, `_userGrid`, `_matchOverlay`, `_consoleMsg`. Run button: tokenize → parse → execute → compare → update UI. Reset: clear editor + canvas. Save/restore code from `SharedPreferences` keyed by date. Celebration animation on solve (green glow pulse on grid cells). |

### Wave 3: Menu Integration & Backend
| Sub-task | Agent | Details |
|----------|-------|---------|
| Wire Pixel.IT into `main.dart` | dart-developer | Add `codeItGame` to `AppView` enum. Add import for `CodeItScreen`. Add `onCodeIT` callback to `MainMenuScreen`. Add switch case for `AppView.codeItGame => CodeItScreen(...)`. |
| Add Pixel.IT card to `main_menu_screen.dart` | dart-developer | Add `VoidCallback onCodeIT` param to constructor. Add `_GameCard(title: 'Pixel.IT', subtitle: 'Daily code puzzle', icon: Icons.code, color: theme.present, onTap: onCodeIT)` in The Lounge section row, after Gamble.IT. |
| Create `frontend/lib/codeit/codeit_service.dart` | dart-developer | Static methods: `postComplete(int attempts)` → POST `/api/codeit/complete`, `getStatus()` → GET `/api/codeit/status`. Same pattern as `SolitaireService` (Bearer token from SharedPreferences). |
| Create `migrations/0022_codeit.sql` | dart-developer | `CREATE TABLE IF NOT EXISTS codeit_completions (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, date TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 1, solved_at TEXT NOT NULL DEFAULT (datetime('now')), UNIQUE(user_id, date));` |
| Create `functions/api/codeit/complete.js` | dart-developer | POST handler. Verify Bearer token → extract userId. UPSERT into `codeit_completions` with user_id, today's date, attempts. Return `{ ok: true }`. |
| Create `functions/api/codeit/status.js` | dart-developer | GET handler. Verify Bearer token → extract userId. Query `codeit_completions` for user_id + today's date. Return `{ solved: true/false, attempts }`. |

### Wave 4: Review
| Sub-task | Agent | Details |
|----------|-------|---------|
| Review all changes | reviewer | Full review against spec and codebase conventions. Verify: DSL handles all edge cases from spec, grid generation is deterministic, UI matches layout spec, menu integration follows existing patterns, backend auth matches other endpoints, no unused imports or dead code. |

## Files Expected to Change

**New files (create):**
- `frontend/lib/codeit/dsl/errors.dart`
- `frontend/lib/codeit/dsl/ast.dart`
- `frontend/lib/codeit/dsl/tokenizer.dart`
- `frontend/lib/codeit/dsl/parser.dart`
- `frontend/lib/codeit/dsl/executor.dart`
- `frontend/lib/codeit/puzzle_generator.dart`
- `frontend/lib/codeit/widgets/pixel_grid.dart`
- `frontend/lib/codeit/widgets/code_editor.dart`
- `frontend/lib/codeit/widgets/console_output.dart`
- `frontend/lib/codeit/codeit_screen.dart`
- `frontend/lib/codeit/codeit_service.dart`
- `functions/api/codeit/complete.js`
- `functions/api/codeit/status.js`
- `migrations/0022_codeit.sql`

**Modified files:**
- `frontend/lib/main.dart` — Add enum value, import, callback, switch case
- `frontend/lib/screens/main_menu_screen.dart` — Add `onCodeIT` callback param and `_GameCard`
