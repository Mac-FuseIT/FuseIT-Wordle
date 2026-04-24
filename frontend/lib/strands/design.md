# Gram.IT — Word Strand Game Design

## Overview

A daily word-strand puzzle integrated into the Fuse Arcade platform. Players find software development themed words hidden in a 6×8 grid of 48 letters by dragging through adjacent cells. Every letter in the grid is used exactly once when the puzzle is solved. One special word — the **spangram** — spans the entire grid edge-to-edge and describes the theme.

---

## Core Game Rules

| Rule | Detail |
|---|---|
| Grid size | 6 columns × 8 rows = 48 letters |
| Theme | Software development / tech themed |
| Spangram | One special word that describes the theme, spans from one edge of the grid to the opposite edge. Highlights **yellow** when found. |
| Theme words | 5–8 words related to the spangram's theme. Highlight **blue** (theme `correct` color) when found. |
| Non-theme words | Valid English words (4+ letters) found in the grid that aren't theme words. Every 3 non-theme words = 1 hint point. |
| Letter paths | Words are formed by dragging through adjacent cells (horizontal, vertical, diagonal). Each cell can only be used once per word. |
| Completion | All theme words + spangram found. Every letter in the grid is used exactly once. |
| Daily | One puzzle per weekday, same for all players. Weekends show Friday's puzzle. |

---

## Hint System

| Hint Level | Cost | Effect |
|---|---|---|
| Level 1 | Click hint button (requires 3 non-theme words banked) | Reveals **which letters** are in one unsolved theme word (unordered, highlighted on grid) |
| Level 2 | Click hint button again (requires another 3 non-theme words) | Reveals the **order** of the letters (shows the word) |

- Hints are earned by finding valid non-theme words in the grid
- Every 3 non-theme words = 1 hint charge
- Hint charges accumulate (find 6 non-theme words = 2 hints available)
- Using a hint first shows scrambled letters, using it again on the same word shows the actual word

---

## Architecture

Reuses the existing Fuse Arcade infrastructure:

- **Frontend**: New Flutter screens/widgets inside `frontend/lib/strands/`
- **Backend**: New API endpoints under `functions/api/strands/`
- **Database**: New tables in the same D1 database
- **Auth**: Uses the same token-based auth

---

## Database Schema

### `strand_puzzles`
| Column | Type | Notes |
|---|---|---|
| `date` | TEXT PRIMARY KEY | `YYYY-MM-DD` |
| `grid` | TEXT NOT NULL | JSON: 6×8 array of letters |
| `theme` | TEXT NOT NULL | Theme description shown to player |
| `spangram` | TEXT NOT NULL | JSON: `{word, path: [[r,c], ...]}` |
| `theme_words` | TEXT NOT NULL | JSON: `[{word, path: [[r,c], ...]}, ...]` |

### `strand_attempts`
| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY | Auto-increment |
| `user_id` | INTEGER NOT NULL | FK → `users.id` |
| `date` | TEXT NOT NULL | `YYYY-MM-DD` |
| `hints_used` | INTEGER NOT NULL DEFAULT 0 | Number of hints used |
| `non_theme_found` | INTEGER NOT NULL DEFAULT 0 | Non-theme words found |
| `completed` | INTEGER NOT NULL DEFAULT 0 | 1 = solved |
| `completed_at` | TEXT | ISO 8601 timestamp |
| UNIQUE | `(user_id, date)` | One attempt per user per day |

### `strand_state`
| Column | Type | Notes |
|---|---|---|
| `user_id` | INTEGER NOT NULL | |
| `date` | TEXT NOT NULL | |
| `found_words` | TEXT NOT NULL DEFAULT '[]' | JSON: words found so far |
| `hint_charges` | INTEGER NOT NULL DEFAULT 0 | Accumulated hint charges |
| `hints_used` | INTEGER NOT NULL DEFAULT 0 | Hints consumed |
| PRIMARY KEY | `(user_id, date)` | |

---

## Puzzle Content — Software Dev Themed

Each puzzle has a theme described by the spangram. Examples:

| Spangram | Theme Words |
|---|---|
| `DEBUGGING` | crash, error, trace, stack, fault, patch |
| `FRONTEND` | react, style, pixel, render, layout |
| `DATABASE` | query, table, index, schema, record, shard |
| `SECURITY` | token, vault, cipher, oauth, firewall |
| `DEVTOOLS` | docker, linux, shell, terminal, deploy |
| `PIPELINE` | build, stage, deploy, test, merge, release |
| `COMPILER` | parse, token, syntax, binary, linker |
| `NETWORKS` | packet, router, socket, proxy, server, port |
| `CLOUDOPS` | scale, deploy, monitor, lambda, container |
| `KEYBOARD` | shift, enter, escape, delete, space, ctrl |

Puzzles are pre-authored as JSON. The grid is constructed so that:
1. The spangram path goes from one edge to the opposite edge
2. Theme word paths fill the remaining cells
3. Every cell is used exactly once
4. All paths use only adjacent cells (including diagonals)

---

## API Endpoints

### `GET /api/strands/today`
- **Auth**: Required
- **Response**: `{ date, grid (6×8 letters), theme (hint text), wordCount (number of theme words + spangram) }`
- Does NOT reveal words or paths.

### `POST /api/strands/check`
- **Auth**: Required
- **Body**: `{ path: [[r,c], [r,c], ...] }`
- Checks if the path forms a theme word, spangram, or valid non-theme word.
- **Response**: `{ type: "spangram"|"theme"|"nontheme"|"invalid", word: "..." }`

### `GET /api/strands/state`
- **Auth**: Required
- **Response**: Current found words, hint charges, hints used.

### `POST /api/strands/hint`
- **Auth**: Required
- **Response**: `{ letters: ["a","b","c"] }` (unordered) or `{ word: "abc" }` (ordered, if second hint on same word)

### `GET /api/strands/leaderboard`
- **Auth**: Required
- **Response**: `{ daily: [{name, hintsUsed, solved}], monthly: [{name, avgHints}] }`
- Daily: sorted by fewest hints used, solved first.
- Monthly: average hints used per puzzle.

---

## Frontend Structure

```
frontend/lib/strands/
├── screens/
│   ├── strands_screen.dart        Main game screen
│   └── strands_leaderboard.dart   Leaderboard
├── widgets/
│   ├── strand_grid.dart           6×8 interactive drag grid
│   └── found_words_list.dart      Shows found words
├── services/
│   └── strands_api.dart           API client
```

---

## UI Layout

```
┌──────────────────────────────────┐
│  ← Gram.IT        💡 Hints: 1 │  ← Header with back + hint button
├──────────────────────────────────┤
│                                  │
│  Theme: "Bug Squashing Tools"    │  ← Theme hint text
│                                  │
│   ┌───┬───┬───┬───┬───┬───┐     │
│   │ D │ E │ B │ U │ G │ S │     │
│   ├───┼───┼───┼───┼───┼───┤     │
│   │ T │ R │ A │ C │ E │ T │     │  ← 6×8 grid
│   ├───┼───┼───┼───┼───┼───┤     │     Drag to select words
│   │ S │ T │ A │ C │ K │ A │     │     Found words highlighted
│   ├───┼───┼───┼───┼───┼───┤     │
│   │ F │ A │ U │ L │ T │ C │     │
│   ├───┼───┼───┼───┼───┼───┤     │
│   │ P │ A │ T │ C │ H │ K │     │
│   ├───┼───┼───┼───┼───┼───┤     │
│   │ E │ R │ R │ O │ R │ E │     │
│   ├───┼───┼───┼───┼───┼───┤     │
│   │ C │ R │ A │ S │ H │ R │     │
│   ├───┼───┼───┼───┼───┼───┤     │
│   │ L │ O │ G │ G │ I │ N │     │
│   └───┴───┴───┴───┴───┴───┘     │
│                                  │
│  Found: CRASH ✓  ERROR ✓        │  ← Found words
│  Theme: 3/7   Non-theme: 2/3    │  ← Progress
│                                  │
└──────────────────────────────────┘
```

### Interaction

- **Drag across cells**: Highlights cells as you drag, forming a path. Adjacent cells only (including diagonals).
- **Release**: Submits the word. If valid theme/spangram, cells highlight permanently. If non-theme valid word, brief flash + hint counter increments. If invalid, cells flash red briefly.
- **Tap hint button**: If hint charges available, reveals letters of one unsolved theme word. Second tap on same word reveals the word itself.
- **Found words**: Listed below the grid with checkmarks. Spangram shown in yellow, theme words in blue/accent.

### Styling

- Uses the same theme system as Guess.IT and Cross.IT
- Unselected cells: theme `tileEmpty` with `present` border
- Dragging path: theme `correct` highlight
- Found spangram cells: yellow/`present` background
- Found theme word cells: blue/`correct` background
- Non-theme flash: brief white flash then reset
- Invalid flash: brief red flash then reset

---

## Scoring & Leaderboard

- **Daily**: Ranked by fewest hints used (0 hints = perfect), solved first
- **Monthly**: Average hints used per puzzle
- **Not attempted**: Counts as max hints (e.g., 5) for monthly average

---

## Main Menu Update

Add a third game card to the main menu:

```
┌────────────┐ ┌────────────┐ ┌────────────┐
│  🔤         │ │  ✚          │ │  🔗         │
│  Guess.IT  │ │  Cross.IT  │ │  Gram.IT │
│  Word Game │ │  Crossword │ │  Word Find │
└────────────┘ └────────────┘ └────────────┘
```

---

## Implementation Order

1. **Database migration**: Create strand tables
2. **Puzzle data**: Author 20+ strand puzzles with dev themes
3. **Puzzle generator**: Build grid from theme words + spangram ensuring all 48 cells used
4. **API — `/api/strands/today`**: Return today's grid + theme
5. **API — `/api/strands/check`**: Validate dragged word paths
6. **API — `/api/strands/state`**: Save/load progress
7. **API — `/api/strands/hint`**: Hint system
8. **API — `/api/strands/leaderboard`**: Hint-based leaderboard
9. **Flutter — StrandGrid widget**: 6×8 drag-to-select grid
10. **Flutter — StrandsScreen**: Main game with theme, progress, hints
11. **Flutter — StrandsLeaderboard**: Leaderboard screen
12. **Flutter — Main menu update**: Add Gram.IT card
13. **Polish**: Drag animations, cell highlighting, theme integration

---

## Puzzle Generation Strategy

Each puzzle is pre-authored because generating valid strand grids algorithmically is extremely complex (every cell must be used exactly once, all paths must be adjacent). The process:

1. Pick a spangram (8-10 letters, dev themed)
2. Pick 5-7 theme words (4-6 letters each, related to spangram)
3. Verify total letters = 48 (pad with shorter theme words if needed)
4. Manually arrange on a 6×8 grid ensuring:
   - Spangram path touches opposite edges
   - All word paths use only adjacent cells
   - No cell is used by two words
   - All 48 cells are covered

Store as JSON with pre-computed paths for server-side validation.

---

## Edge Cases

- **Diagonal dragging**: Must handle touch/mouse drag across diagonal cells
- **Path validation**: Each cell in the path must be adjacent to the previous one
- **Duplicate paths**: Same word found via different path — only accept the correct path
- **Partial words**: If a user drags through cells that form a prefix of a theme word, don't reveal anything until they release
- **Weekend**: Shows Friday's puzzle (same as Guess.IT and Cross.IT)
