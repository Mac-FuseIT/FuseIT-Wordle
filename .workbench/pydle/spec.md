# Pixel.IT — Daily Code Puzzle Design Spec

## Overview

A daily coding puzzle for Fuse Arcade. Players are shown a 5x5 target grid of colored cells and must write Python-like code (a simple DSL) to reproduce the pattern. The DSL parser runs entirely client-side in Dart — no backend needed for gameplay. One puzzle per day, deterministically generated from the date seed so all players get the same target.

## Goals & Non-Goals

**Goals:**
- Daily 5x5 colored grid puzzle, same for everyone each day
- Python-like DSL with for loops, if/else, set_pixel, fill
- Client-side DSL parser and executor (Dart)
- Real-time canvas feedback on "Run"
- Cell-match counter ("X/25 cells match!")
- Celebration on solve ("🎉 Solved in N attempts!")
- Infinite retries — no move limit, no time limit
- Dark theme matching Fuse Arcade aesthetic
- Located under "The Lounge" in main menu
- Optional: save completion status to backend

**Non-Goals:**
- Leaderboard or scoring system
- Lobby or multiplayer
- Syntax highlighting (nice-to-have, not required)
- Custom variable assignment (only loop vars x, y)
- Backend-validated execution
- WebSocket connections
- Undo history for code edits

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter Web Frontend                                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Pixel.IT Game Screen                                      ││
│  │ - Target grid (5x5, generated from date seed)           ││
│  │ - User canvas (5x5, updated on Run)                     ││
│  │ - Code editor (multi-line, monospace)                    ││
│  │ - Run / Reset buttons                                   ││
│  │ - Console output (match count or errors)                ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ DSL Engine (all client-side Dart)                        ││
│  │ - Tokenizer → Parser → AST → Executor                  ││
│  │ - Step limit (10,000) for infinite loop protection      ││
│  │ - Error reporting with line numbers                     ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Puzzle Generator (client-side, deterministic)            ││
│  │ - Seeded RNG from date string                           ││
│  │ - Picks 2-4 colors, fills 5x5 grid randomly            ││
│  └─────────────────────────────────────────────────────────┘│
└──────────────────────────────────┬──────────────────────────┘
                                   │ Optional REST (Bearer token)
                                   ▼
┌─────────────────────────────────────────────────────────────┐
│  Cloudflare Pages Functions (optional)                       │
│  - POST /api/codeit/complete → mark today as solved          │
│  - GET  /api/codeit/status   → check if solved today         │
└──────────────────────────────────┬──────────────────────────┘
                                   │ D1 binding
                                   ▼
┌─────────────────────────────────────────────────────────────┐
│  D1 Database (fuseit-wordle-db)                              │
│  - codeit_completions (user_id, date, attempts, solved_at)   │
└─────────────────────────────────────────────────────────────┘
```

All gameplay logic is client-side. The backend is optional and only tracks whether a user solved today's puzzle (for showing a checkmark in the menu).

---

## Puzzle Generation Algorithm

The target grid is generated deterministically from the current date. Every client runs the same algorithm, producing the same grid for the same day.

### Seed Derivation

```dart
int _dateToSeed(DateTime date) {
  // Use date string "2026-07-22" hashed to an integer
  final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  // Simple hash: sum of char codes * primes
  int hash = 0;
  for (int i = 0; i < dateStr.length; i++) {
    hash = (hash * 31 + dateStr.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return hash;
}
```

### Seeded RNG

Use a simple Linear Congruential Generator (LCG) for cross-platform determinism:

```dart
class SeededRng {
  int _state;
  SeededRng(this._state);

  int nextInt(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state % max;
  }
}
```

### Grid Generation

```dart
const allColors = ['black', 'red', 'blue', 'yellow', 'green', 'white', 'purple', 'orange'];

List<List<String>> generateTarget(DateTime date) {
  final rng = SeededRng(_dateToSeed(date));

  // Pick 2-4 colors for today's puzzle
  final numColors = 2 + rng.nextInt(3); // 2, 3, or 4
  final shuffled = List<String>.from(allColors);
  // Fisher-Yates shuffle first numColors
  for (int i = shuffled.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }
  final palette = shuffled.sublist(0, numColors);

  // Fill 5x5 grid randomly from palette
  return List.generate(5, (x) =>
    List.generate(5, (y) => palette[rng.nextInt(numColors)]));
}
```

### Puzzle Number

Puzzle number displayed in the header, counting from a fixed epoch:

```dart
int puzzleNumber(DateTime date) {
  final epoch = DateTime(2026, 7, 22); // launch date
  return date.difference(epoch).inDays + 1;
}
```

---

## DSL Language Specification

The DSL is a subset of Python syntax, parsed and executed entirely in Dart. It supports enough to express grid patterns concisely.

### Grammar (informal)

```
program     := statement*
statement   := for_stmt | if_stmt | func_call
for_stmt    := 'for' IDENT 'in' 'range' '(' expr ')' ':' NEWLINE INDENT block DEDENT
if_stmt     := 'if' condition ':' NEWLINE INDENT block DEDENT ('else' ':' NEWLINE INDENT block DEDENT)?
block       := statement+
func_call   := IDENT '(' arg_list ')'
arg_list    := expr (',' expr)*
condition   := expr COMP_OP expr
expr        := NUMBER | STRING | IDENT | expr '%' expr | expr '+' expr | expr '-' expr
COMP_OP     := '==' | '!=' | '>' | '<' | '>=' | '<='
IDENT       := [a-z_][a-z0-9_]*
NUMBER      := [0-9]+
STRING      := '\'' [^']* '\''
```

### Built-in Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `set_pixel` | `set_pixel(x, y, color)` | Set cell at (x, y) to `color`. x=column (0-4), y=row (0-4) |
| `fill` | `fill(color)` | Set all 25 cells to `color` |

### Supported Constructs

| Construct | Example | Notes |
|-----------|---------|-------|
| For loop | `for x in range(5):` | Loop variable scoped to block. Only `range(n)` supported. |
| Nested for | `for x in range(5):\n    for y in range(5):` | Up to 3 levels deep |
| If | `if x == 2:` | Condition on loop vars, numbers, modulo |
| If-else | `if x > y:\n    ...\nelse:\n    ...` | Single else, no elif |
| Modulo | `if x % 2 == 0:` | Modulo in conditions and expressions |
| Arithmetic | `x + 1`, `y - 2` | Addition and subtraction in expressions |

### Available Variables

Only loop-bound variables are available. No custom variable assignment.
- `x`, `y` — common loop variable names
- Any single-letter or short identifier used in a `for` statement becomes available inside that loop's block

### Color Strings

Valid color values (case-insensitive during parsing, stored lowercase):
- `'black'`, `'red'`, `'blue'`, `'yellow'`, `'green'`, `'white'`, `'purple'`, `'orange'`

### Indentation Rules

- Each indentation level = 4 spaces (or 1 tab, normalized to 4 spaces)
- Mixed tabs/spaces are normalized
- Blank lines are ignored
- Trailing whitespace is stripped

### Execution Limits

| Limit | Value | Error Message |
|-------|-------|---------------|
| Max steps | 10,000 | "Execution limit reached (too many steps)" |
| Max nesting | 3 levels | "Too many nested loops (max 3)" |
| Grid bounds | 0-4 | "Index out of range: x=5 is outside 0-4" |

---

## DSL Parser Design

The parser has three stages: Tokenizer → Parser → Executor.

### Stage 1: Tokenizer

Splits source code into a list of `Token` objects. Each token has a type, value, and line number.

```dart
enum TokenType {
  forKeyword, inKeyword, rangeKeyword, ifKeyword, elseKeyword,
  identifier, number, string, colon, comma,
  lparen, rparen, percent, plus, minus,
  equals, notEquals, greaterThan, lessThan, greaterEqual, lessEqual,
  newline, indent, dedent, eof
}

class Token {
  final TokenType type;
  final String value;
  final int line;
}
```

**Indentation handling:**
1. Split source into lines, strip trailing whitespace
2. Skip blank lines
3. For each line, count leading spaces (normalize tabs → 4 spaces)
4. Compare to previous indent level:
   - Greater → emit INDENT token
   - Less → emit one or more DEDENT tokens
   - Same → continue
5. Tokenize the line content left-to-right

### Stage 2: Parser

Builds an AST from the token stream. Recursive descent parser.

```dart
abstract class AstNode {}

class ProgramNode extends AstNode {
  final List<AstNode> statements;
}

class ForNode extends AstNode {
  final String variable;   // loop var name
  final AstNode rangeExpr; // the number in range(n)
  final List<AstNode> body;
}

class IfNode extends AstNode {
  final Condition condition;
  final List<AstNode> thenBody;
  final List<AstNode>? elseBody;
}

class FuncCallNode extends AstNode {
  final String name;       // "set_pixel" or "fill"
  final List<AstNode> args;
}

class NumberLiteral extends AstNode { final int value; }
class StringLiteral extends AstNode { final String value; }
class VariableRef extends AstNode { final String name; }
class BinaryExpr extends AstNode {
  final AstNode left;
  final String op; // '%', '+', '-'
  final AstNode right;
}

class Condition {
  final AstNode left;
  final String op; // '==', '!=', '>', '<', '>=', '<='
  final AstNode right;
}
```

### Stage 3: Executor

Walks the AST, maintains a variable scope (stack of maps), and modifies a 5x5 grid.

```dart
class ExecutionResult {
  final List<List<String>> grid; // 5x5, default all 'black'
  final String? error;           // null if success
  final int steps;               // total steps executed
}

class DslExecutor {
  int _steps = 0;
  static const maxSteps = 10000;
  final Map<String, int> _vars = {};
  late List<List<String>> _grid;

  ExecutionResult execute(ProgramNode program) {
    _grid = List.generate(5, (_) => List.generate(5, (_) => 'black'));
    _steps = 0;
    try {
      _execBlock(program.statements);
      return ExecutionResult(grid: _grid, error: null, steps: _steps);
    } on DslError catch (e) {
      return ExecutionResult(grid: _grid, error: e.message, steps: _steps);
    }
  }

  void _execBlock(List<AstNode> stmts) {
    for (final stmt in stmts) {
      _steps++;
      if (_steps > maxSteps) throw DslError('Execution limit reached (too many steps)');
      _execStmt(stmt);
    }
  }

  void _execStmt(AstNode node) {
    if (node is ForNode) {
      final n = _evalExpr(node.rangeExpr);
      for (int i = 0; i < n; i++) {
        _vars[node.variable] = i;
        _execBlock(node.body);
      }
      _vars.remove(node.variable);
    } else if (node is IfNode) {
      if (_evalCondition(node.condition)) {
        _execBlock(node.thenBody);
      } else if (node.elseBody != null) {
        _execBlock(node.elseBody!);
      }
    } else if (node is FuncCallNode) {
      _execFunc(node);
    }
  }

  void _execFunc(FuncCallNode node) {
    switch (node.name) {
      case 'set_pixel':
        if (node.args.length != 3) throw DslError('set_pixel takes 3 arguments (x, y, color)');
        final x = _evalExpr(node.args[0]);
        final y = _evalExpr(node.args[1]);
        final color = _evalString(node.args[2]);
        if (x < 0 || x > 4) throw DslError('Index out of range: x=$x is outside 0-4');
        if (y < 0 || y > 4) throw DslError('Index out of range: y=$y is outside 0-4');
        if (!validColors.contains(color)) {
          throw DslError("Unknown color '$color'. Available: ${validColors.join(', ')}");
        }
        _grid[x][y] = color;
      case 'fill':
        if (node.args.length != 1) throw DslError('fill takes 1 argument (color)');
        final color = _evalString(node.args[0]);
        if (!validColors.contains(color)) {
          throw DslError("Unknown color '$color'. Available: ${validColors.join(', ')}");
        }
        for (int i = 0; i < 5; i++) {
          for (int j = 0; j < 5; j++) { _grid[i][j] = color; }
        }
      default:
        throw DslError("Unknown function '${node.name}'");
    }
  }

  static const validColors = ['black', 'red', 'blue', 'yellow', 'green', 'white', 'purple', 'orange'];
}
```

---

## UI Layout & Widgets

### Screen Structure

```
┌─────────────────────────────────────────────────────────────┐
│  ← Back            Pixel.IT           Puzzle #143            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐          ┌─────────────┐                  │
│  │ Your Canvas │          │   Target    │                  │
│  │   5x5       │          │    5x5      │                  │
│  │             │          │             │                  │
│  └─────────────┘          └─────────────┘                  │
│   "Your Output"            "Target"                         │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Code Editor                                          │   │
│  │ > for x in range(5):                                │   │
│  │ >     for y in range(5):                            │   │
│  │ >         set_pixel(x, y, 'red')                    │   │
│  │                                                      │   │
│  │                                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  [▶ Run]                                     [↺ Reset]     │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Console: 25/25 cells match! 🎉                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Widget Tree

```
CodeItScreen (StatefulWidget)
├── AppBar (Back button, "Pixel.IT" title, puzzle number)
├── GridRow (Row)
│   ├── PixelGrid (user canvas, 5x5)
│   │   └── GridCell × 25 (colored Container with border)
│   └── PixelGrid (target, 5x5)
│       └── GridCell × 25
├── CodeEditor (TextField, multi-line, monospace)
├── ButtonRow
│   ├── RunButton (ElevatedButton, green accent)
│   └── ResetButton (OutlinedButton)
└── ConsoleOutput (Text widget, shows match count or error)
```

### Widget Details

**PixelGrid:**
- 5x5 grid of colored squares
- Each cell ~40x40px with 1px border (dark grey)
- After running, user canvas cells get overlay:
  - Matching cell: subtle green border or checkmark icon
  - Non-matching cell: subtle red border
- Target grid has no overlay, just shows colors

**CodeEditor:**
- Multi-line `TextField` with `TextEditingController`
- Monospace font (`'Courier New'` or system monospace)
- Dark background (#1E1E1E), light text (#D4D4D4)
- Min height: 8 lines visible, scrollable
- Tab key inserts 4 spaces (custom key handler)
- No line numbers in v1 (future enhancement)

**ConsoleOutput:**
- Single line or multi-line text area below buttons
- Shows one of:
  - `"X/25 cells match"` (white text)
  - `"🎉 Perfect! All 25 cells match! Solved in N attempts!"` (green text)
  - `"Error on line 3: Unknown function 'setpixel'"` (red text)

**RunButton:**
- Accent-colored (theme.correct / green)
- Shows "▶ Run" label
- On press: parse code → execute → update canvas → show result

**ResetButton:**
- Outlined, secondary
- Clears the code editor and resets user canvas to blank

---

## Color Palette & Visual Design

### Grid Cell Colors (game colors)

| Color Name | Hex Value | Notes |
|-----------|-----------|-------|
| black | `#000000` | |
| red | `#E74C3C` | Bright red |
| blue | `#3498DB` | Sky blue |
| yellow | `#F1C40F` | Golden yellow |
| green | `#2ECC71` | Emerald green |
| white | `#FFFFFF` | |
| purple | `#9B59B6` | Medium purple |
| orange | `#E67E22` | Warm orange |

### UI Theme Colors

- Background: `#121213` (matches Fuse Arcade)
- Code editor bg: `#1E1E1E`
- Code editor text: `#D4D4D4`
- Grid cell border: `#333333`
- Match overlay (correct): `#2ECC71` at 30% opacity border
- Mismatch overlay (wrong): `#E74C3C` at 30% opacity border
- Button accent: uses `theme.correct` from AppTheme
- Console error text: `#E74C3C`
- Console success text: `#2ECC71`

### Grid Cell Rendering

- Each cell: 40×40 pixels (responsive — scale with available width)
- Border: 1px solid `#333333`
- Border radius: 2px (subtle)
- Gap between cells: 2px
- After comparison:
  - Matching cells: 2px green border
  - Non-matching cells: 2px red border

---

## Error Handling

### Error Categories

| Category | Example | Display |
|----------|---------|---------|
| Syntax | `for x in range(5)` (missing colon) | "Line 1: Expected ':' after range expression" |
| Syntax | `set_pixel(x y 'red')` (missing commas) | "Line 1: Expected ',' between arguments" |
| Runtime | `set_pixel(5, 0, 'red')` | "Line 1: Index out of range: x=5 is outside 0-4" |
| Runtime | `set_pixel(0, 0, 'redd')` | "Line 1: Unknown color 'redd'. Available: black, red, blue, yellow, green, white, purple, orange" |
| Runtime | Unknown function | "Line 1: Unknown function 'setpixel'. Did you mean 'set_pixel'?" |
| Limit | Infinite loop | "Execution limit reached (too many steps)" |
| Indent | Bad indentation | "Line 3: Unexpected indentation" |

### Error Display

- Errors shown in console output area in red text
- Only first error is shown (stop on first error)
- Line numbers are 1-indexed (human-friendly)
- Parser stops at first syntax error; executor stops at first runtime error

### Friendly Suggestions

For common mistakes, provide hints:
- `setpixel` → "Did you mean 'set_pixel'?"
- `set_Pixel` → "Did you mean 'set_pixel'?"
- `pixel` → "Unknown function 'pixel'. Available: set_pixel, fill"
- Missing quotes around color → "Expected string for color argument"

---

## Success & Failure Feedback

### On Run (not solved)

```
Console: "18/25 cells match"
```
- User canvas updates to show their output
- Comparison overlay shows which cells match/don't match
- Attempt counter increments

### On Solve

```
Console: "🎉 Perfect! All 25 cells match! Solved in 4 attempts!"
```
- Brief celebration animation (confetti or glow effect)
- Grid cells pulse with green glow
- Code editor remains editable (user can still experiment)
- If backend integration is enabled, POST completion to server

### On Error

```
Console: "Error on line 3: Index out of range: x=5 is outside 0-4"
```
- User canvas shows partial result (whatever executed before the error)
- Error text in red
- Does NOT count as an attempt for the solve counter

---

## Main Menu Integration

### Changes to `main.dart`

Add a new `AppView` enum value:
```dart
enum AppView { ..., codeItGame }
```

Add navigation callback to `MainMenuScreen`:
```dart
onCodeIT: () => setState(() => _view = AppView.codeItGame),
```

Add the screen case:
```dart
AppView.codeItGame => CodeItScreen(
  theme: _theme,
  userId: _userId!,
  onBack: () => setState(() => _view = AppView.menu),
),
```

### Changes to `main_menu_screen.dart`

Add `Pixel.IT` card under "The Lounge" section alongside Chess.IT and Gamble.IT:

```dart
_GameCard(
  title: 'Pixel.IT',
  subtitle: 'Daily code puzzle',
  icon: Icons.code,
  color: theme.present,
  onTap: onCodeIT,
),
```

---

## Edge Cases

| Case | Behavior |
|------|----------|
| Empty code | Canvas stays blank (all black). Console: "0/25 cells match" |
| Only whitespace/comments | Same as empty code |
| Infinite loop (`for x in range(99999):`) | Stops at 10,000 steps, shows error |
| Out-of-bounds set_pixel | Runtime error, partial grid shown |
| Code doesn't cover all cells | Uncovered cells stay default 'black' |
| Very long code (>100 lines) | Allow it — editor scrolls |
| Invalid indentation (3 spaces) | Error: "Unexpected indentation (expected multiple of 4 spaces)" |
| `range(0)` | Loop body never executes (valid, no error) |
| `range(-1)` | Loop body never executes (valid, no error) |
| Nested loops >3 deep | Error at parse time: "Too many nested loops (max 3)" |
| Multiple `fill()` calls | Last one wins (each overwrites entire grid) |
| `set_pixel` after `fill` | set_pixel overwrites specific cell |
| User refreshes page | Code is lost (no persistence in v1). Target regenerates same. |
| Midnight rollover | New puzzle. Previous code is irrelevant. |

---

## Optional Backend Integration

### Database Schema

Migration file: `migrations/0022_codeit.sql`

```sql
CREATE TABLE IF NOT EXISTS codeit_completions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 1,
  solved_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, date)
);
```

### API Endpoints

**POST /api/codeit/complete**
```json
Request:  { "attempts": 4 }
Response: { "ok": true }
```
Called once when user solves the puzzle. Idempotent (UPSERT on user_id + date).

**GET /api/codeit/status**
```json
Response: { "solved": true, "attempts": 4 }
// or
Response: { "solved": false }
```
Used by menu screen to show a checkmark if today's puzzle is already solved.

### Backend Files

- `functions/api/codeit/complete.js` — POST handler
- `functions/api/codeit/status.js` — GET handler

Both use Bearer token auth (same pattern as other endpoints).

---

## File Structure

```
frontend/lib/codeit/
├── codeit_screen.dart           Main game screen widget
├── dsl/
│   ├── tokenizer.dart           Tokenizer (source → tokens)
│   ├── parser.dart              Parser (tokens → AST)
│   ├── ast.dart                 AST node definitions
│   ├── executor.dart            Executor (AST → grid)
│   └── errors.dart              DslError class
├── puzzle_generator.dart        Deterministic grid generation
├── widgets/
│   ├── pixel_grid.dart          5x5 colored grid widget
│   ├── code_editor.dart         Monospace text editor widget
│   └── console_output.dart      Result/error display widget
└── codeit_service.dart          Optional API calls (complete/status)

functions/api/codeit/
├── complete.js                  POST /api/codeit/complete
└── status.js                    GET /api/codeit/status

migrations/
└── 0022_codeit.sql              Completions table
```

---

## Design Decisions

### 1. Fully Client-Side Execution

**Decision:** DSL parsing and execution happens entirely in Dart on the client.

**Rationale:** The puzzle is deterministic from the date — no server secret needed. Client-side execution means zero latency on "Run", no API calls during gameplay, and simpler architecture. The optional backend only tracks completion for UX polish (menu checkmarks).

### 2. Custom DSL Instead of Real Python

**Decision:** Build a small, purpose-built parser rather than embedding a Python interpreter.

**Rationale:** A real Python interpreter (via WASM or JS bridge) would be heavyweight (~2MB+), slow to load, and introduce security concerns. Our DSL only needs for loops, if/else, and two functions — a recursive descent parser for this is ~300 lines of Dart. It looks like Python to the user but is much simpler to implement and sandbox.

### 3. No Variable Assignment

**Decision:** Users cannot define custom variables. Only loop vars (`x`, `y`, etc.) exist.

**Rationale:** Keeps the parser simple. The puzzles are 5x5 grids — all patterns can be expressed with nested loops and conditionals over loop variables. Adding assignment would require scope management and significantly complicate the executor.

### 4. Random Grid (Not Pattern-Based)

**Decision:** Target grids are purely random (seeded), not hand-crafted patterns.

**Rationale:** Hand-crafting 365+ puzzles is unsustainable for ~38 users. Random grids ensure infinite variety. Some days will be easy (2 colors, simple pattern), some hard (4 colors, complex). This variance keeps it interesting. Users can always brute-force with 25 individual `set_pixel` calls — the fun is finding elegant solutions.

### 5. No Scoring or Leaderboard

**Decision:** No competitive element. Just "solved" or "not solved."

**Rationale:** The game is a creative coding sandbox. Different solutions have different elegance but measuring "best solution" (fewest lines? fewest tokens?) adds complexity and discourages experimentation. Keep it simple — the satisfaction is in solving it.

### 6. Default Grid Color is Black

**Decision:** Before any code runs, all cells are 'black'.

**Rationale:** Provides a sensible default. Users can use `fill()` to set a base color, then `set_pixel()` for specifics. Black as default means the grid looks intentionally blank (dark theme), not broken.

### 7. Tab Key Inserts Spaces

**Decision:** Pressing Tab in the code editor inserts 4 spaces instead of navigating focus.

**Rationale:** Critical for usability. The DSL is indentation-based — users need Tab to indent code naturally. Implement via `RawKeyboardListener` or `FocusNode` key handler on the TextField.

---

## Tasks

1. **Create puzzle generator** — Implement `SeededRng` and `generateTarget()` in `puzzle_generator.dart` — S
2. **Define AST nodes** — Create `ast.dart` with all node classes — S
3. **Build tokenizer** — Implement `tokenizer.dart` (line splitting, indentation, token extraction) — M
4. **Build parser** — Implement `parser.dart` (recursive descent, produces AST) — M
5. **Build executor** — Implement `executor.dart` (walks AST, modifies grid, enforces limits) — M
6. **Create PixelGrid widget** — 5x5 colored grid with comparison overlay — S
7. **Create CodeEditor widget** — Monospace TextField with Tab handling — S
8. **Create ConsoleOutput widget** — Error/success display — S
9. **Build CodeItScreen** — Main game screen composing all widgets — M
10. **Wire into main menu** — Add AppView, callback, and game card to "The Lounge" — S
11. **Add celebration animation** — Confetti or glow on solve — S
12. **Create backend migration** — `0022_codeit.sql` — S
13. **Create backend endpoints** — `complete.js` and `status.js` — S
14. **Integrate completion tracking** — Call API on solve, show checkmark in menu — S

**Total estimated effort:** ~2-3 days

---

## Open Questions

1. **Code persistence:** Should we save the user's code in localStorage so they don't lose it on refresh? (Recommendation: yes, easy win with `SharedPreferences`)
2. **Hint system:** Should there be a "Show hint" button that reveals one correct `set_pixel` call? (Recommendation: defer to v2)
3. **Solution sharing:** Should users be able to share their solution code (like Wordle share)? (Recommendation: nice-to-have for v2, show code length: "Solved Pixel.IT #143 in 4 lines!")
4. **elif support:** Should we add `elif` to the DSL? (Recommendation: defer — `else` + nested `if` works for v1)
