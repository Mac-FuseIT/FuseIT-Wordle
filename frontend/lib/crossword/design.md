# Cross.IT — Mini Crossword Game Design

## Overview

A daily mini crossword puzzle integrated into the Fuse Arcade platform. Each day a new 5×5 crossword grid is generated with tech/dev-themed clues. Players fill in words across and down, with intersecting letters helping solve the puzzle. Completion time is tracked and displayed on a leaderboard.

---

## Core Game Rules

| Rule | Detail |
|---|---|
| Grid size | 5×5 |
| Clues | 5 Across + 5 Down (some cells may be blacked out) |
| Word length | 3–5 letters |
| Input | Tap a cell to select, type to fill, Tab/click to switch direction |
| Completion | All cells filled correctly |
| Scoring | Time to complete (lower is better) |
| Daily | One puzzle per day, same for all players |

---

## Architecture

Reuses the existing Guess.IT infrastructure:

- **Frontend**: New Flutter screens/widgets inside `frontend/lib/crossword/`
- **Backend**: New API endpoints under `functions/api/crossword/`
- **Database**: New tables in the same D1 database
- **Auth**: Uses the same token-based auth from Guess.IT

---

## Database Schema (new tables)

### `crossword_puzzles`
| Column | Type | Notes |
|---|---|---|
| `date` | TEXT PRIMARY KEY | `YYYY-MM-DD` |
| `grid` | TEXT NOT NULL | JSON: 5×5 array of letters, `null` for black cells |
| `clues_across` | TEXT NOT NULL | JSON: `[{number, clue, row, col, length}]` |
| `clues_down` | TEXT NOT NULL | JSON: `[{number, clue, row, col, length}]` |

### `crossword_attempts`
| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY | Auto-increment |
| `user_id` | INTEGER NOT NULL | FK → `users.id` |
| `date` | TEXT NOT NULL | `YYYY-MM-DD` |
| `time_seconds` | INTEGER NOT NULL | Time to complete in seconds |
| `completed_at` | TEXT | ISO 8601 timestamp |
| UNIQUE | `(user_id, date)` | One attempt per user per day |

### `crossword_state`
| Column | Type | Notes |
|---|---|---|
| `user_id` | INTEGER NOT NULL | FK → `users.id` |
| `date` | TEXT NOT NULL | `YYYY-MM-DD` |
| `grid` | TEXT NOT NULL | JSON: user's current grid state |
| `elapsed` | INTEGER NOT NULL DEFAULT 0 | Seconds elapsed so far |
| PRIMARY KEY | `(user_id, date)` | |

---

## Puzzle Generation

Puzzles are pre-authored as JSON and stored in a JS file (like the word list for Guess.IT). Each puzzle contains:

```json
{
  "grid": [
    ["C","O","D","E","S"],
    ["L",null,"A","R","A"],
    ["O","A","T","A","S"],
    ["N","U","H",null,"K"],
    ["E","T","S","S","S"]
  ],
  "across": [
    {"number": 1, "clue": "Source ___", "row": 0, "col": 0, "length": 5},
    {"number": 4, "clue": "Data structure for key-value pairs", "row": 1, "col": 2, "length": 3},
    {"number": 5, "clue": "Breakfast grain", "row": 2, "col": 0, "length": 5},
    {"number": 6, "clue": "Authentication standard", "row": 3, "col": 0, "length": 3},
    {"number": 7, "clue": "Secure Shell", "row": 4, "col": 0, "length": 5}
  ],
  "down": [
    {"number": 1, "clue": "Git operation", "row": 0, "col": 0, "length": 5},
    {"number": 2, "clue": "Automation tool", "row": 1, "col": 1, "length": 4},
    {"number": 3, "clue": "File ___", "row": 0, "col": 2, "length": 5},
    {"number": 4, "clue": "Arrays in Python", "row": 0, "col": 4, "length": 5}
  ]
}
```

Selection is deterministic using the same date-hash approach as Guess.IT.

---

## API Endpoints

### `GET /api/crossword/today`
- **Auth**: Required
- **Response**: `{ date, grid (with nulls for black cells, empty strings for unsolved), cluesAcross, cluesDown }`
- Does NOT reveal answers.

### `GET /api/crossword/state`
- **Auth**: Required
- **Response**: Current user's grid state and elapsed time, or completed status.

### `POST /api/crossword/update`
- **Auth**: Required
- **Body**: `{ grid: [[...]], elapsed: 45 }`
- Saves in-progress state.

### `POST /api/crossword/complete`
- **Auth**: Required
- **Body**: `{ grid: [[...]], elapsed: 120 }`
- Validates the grid against the answer. If correct, saves to `crossword_attempts`.
- **Response**: `{ correct: true/false, timeSeconds: 120 }`

### `GET /api/crossword/leaderboard`
- **Auth**: Required
- **Response**: `{ daily: [{name, timeSeconds}], monthly: [{name, totalTime}] }`
- Daily: sorted by fastest time.
- Monthly: sum of daily times. Missed days get a penalty of 600 seconds (10 minutes).

---

## Frontend Structure

```
frontend/lib/crossword/
├── screens/
│   ├── crossword_screen.dart      Main game screen
│   └── crossword_leaderboard.dart Leaderboard for crossword
├── widgets/
│   ├── crossword_grid.dart        5×5 interactive grid
│   ├── clue_list.dart             Across/Down clue panels
│   └── timer_display.dart         Running timer
├── models/
│   └── crossword_puzzle.dart      Data classes
└── services/
    └── crossword_api.dart         API client
```

---

## UI Layout

```
┌──────────────────────────────────┐
│  Guess.IT    Cross.IT   ⏱ 1:23  │  ← Header with game tabs + timer
├──────────────────────────────────┤
│                                  │
│   ┌───┬───┬───┬───┬───┐         │
│   │ C │ O │ D │ E │ S │  1→     │
│   ├───┼───┼───┼───┼───┤         │
│   │   │███│ A │ R │ A │  4→     │
│   ├───┼───┼───┼───┼───┤         │
│   │ O │ A │ T │ A │ S │  5→     │
│   ├───┼───┼───┼───┼───┤         │
│   │ N │ U │ H │███│ K │  6→     │
│   ├───┼───┼───┼───┼───┤         │
│   │ E │ T │ S │ S │ S │  7→     │
│   └───┴───┴───┴───┴───┘         │
│    1↓  2↓  3↓      4↓           │
│                                  │
│  ACROSS          DOWN            │
│  1. Source ___   1. Git op       │
│  4. Key-value   2. Auto tool    │
│  5. Grain       3. File ___     │
│  ...            ...              │
│                                  │
└──────────────────────────────────┘
```

### Interaction

- **Tap a cell**: Selects it, highlights the word (across or down)
- **Tap same cell again**: Toggles between across/down direction
- **Type a letter**: Fills the cell, auto-advances to next cell in the word
- **Backspace**: Clears current cell, moves back
- **Tap a clue**: Selects and highlights that word in the grid
- **Timer**: Starts on first interaction, pauses if you leave the page
- **Completion**: When all cells are correct, timer stops, celebration animation, leaderboard shown

### Styling

- Uses the same theme system as Guess.IT
- Selected cell: bright border
- Selected word: subtle highlight
- Correct word (all letters filled): slightly different shade
- Black cells: solid dark color
- Numbers in top-left corner of starting cells

---

## Main Menu Design

A new home screen that shows both games:

```
┌──────────────────────────────────┐
│          Guess.IT                │  ← App name
│                                  │
│   ┌────────────┐ ┌────────────┐  │
│   │            │ │            │  │
│   │  🔤        │ │  ✚         │  │
│   │  Guess.IT  │ │  Cross.IT  │  │
│   │  Word Game │ │  Crossword │  │
│   │            │ │            │  │
│   └────────────┘ └────────────┘  │
│                                  │
│   mekhail              [logout]  │
└──────────────────────────────────┘
```

---

## Implementation Order

1. **Database migration**: Create crossword tables
2. **Puzzle data**: Author 30+ mini crossword puzzles with tech clues
3. **API — `/api/crossword/today`**: Return today's puzzle
4. **API — `/api/crossword/state`**: Save/load in-progress state
5. **API — `/api/crossword/complete`**: Validate and record completion
6. **API — `/api/crossword/leaderboard`**: Time-based leaderboard
7. **Flutter — CrosswordGrid widget**: Interactive 5×5 grid
8. **Flutter — ClueList widget**: Across/Down clue panels
9. **Flutter — CrosswordScreen**: Main game screen with timer
10. **Flutter — CrosswordLeaderboard**: Leaderboard screen
11. **Flutter — Main menu**: Game selection screen
12. **Polish**: Animations, theme integration, responsive layout

---

## Puzzle Content Strategy

Puzzles are tech-themed where possible:
- Clues reference programming concepts, tools, languages, cloud services
- Mix of easy (e.g. "Version control system" → GIT) and medium (e.g. "Container orchestration tool" → KUBE)
- Some general knowledge clues to keep it accessible
- Need 30+ puzzles minimum for a month of daily play
- Puzzles cycle deterministically using the date hash

---

## Scoring & Leaderboard

- **Daily**: Ranked by completion time (fastest first)
- **Monthly**: Sum of daily times. Missed days = 600s penalty (10 min)
- **Not completed**: If a user starts but doesn't finish, they get the 600s penalty at end of day
- Same leaderboard style as Guess.IT with user highlighting and monthly breakdown
