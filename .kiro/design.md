# FuseIT Wordle — Project Design

## Overview

A Wordle-inspired daily word game deployed on Cloudflare's free tier. Each day a new word is selected with a varying length (4–8 letters). Players guess the word with color-coded feedback (green/yellow/grey). Users log in with just a name, and leaderboards track daily and monthly performance.

---

## Core Game Rules

| Rule | Detail |
|---|---|
| Word length | Varies daily: 4, 5, 6, 7, or 8 letters |
| Allowed attempts | Word length + 1 (e.g. 6-letter word → 7 attempts) |
| Letter feedback | **Green** = correct letter, correct position · **Yellow** = correct letter, wrong position · **Grey** = letter not in word |
| Daily word selection | One word per day, deterministic (same for all players) |
| Missed day penalty | If a user doesn't attempt the day's word, they receive the maximum attempts (word length + 1) added to their monthly total |

---

## Tech Stack (Cloudflare Free Tier)

| Layer | Technology | Why |
|---|---|---|
| Frontend | **Flutter Web** (Dart) | Compiles to static HTML/CSS/JS via `flutter build web`, deployed to **Cloudflare Pages** (free). Enables future mobile app reuse. |
| Backend API | **Cloudflare Workers** (free: 100k requests/day) | Handles word selection, guess validation, leaderboard queries |
| Database | **Cloudflare D1** (free: 5 GB storage, 5M rows read/day) | SQLite-based, stores users, daily words, and attempt records |
| Hosting | **Cloudflare Pages** | Auto-deploys from Git, serves static frontend |

---

## Architecture

```
┌─────────────────────────────────┐
│     Flutter Web App (Dart)      │
│  (Compiled to static JS/HTML)   │
│     Hosted on Cloudflare Pages  │
└──────────────┬──────────────────┘
               │ HTTP (dart:http / dio)
               ▼
┌─────────────────────────────────┐
│       Cloudflare Worker         │
│  (API: /api/login, /api/guess,  │
│   /api/today, /api/leaderboard) │
└──────────────┬──────────────────┘
               │ SQL
               ▼
┌─────────────────────────────────┐
│        Cloudflare D1            │
│  (users, words, attempts)       │
└─────────────────────────────────┘
```

The Worker is attached to Pages via **Cloudflare Pages Functions** (file-based routing under `functions/`), so everything deploys as a single Pages project — no separate Worker deployment needed.

---

## Database Schema (D1 / SQLite)

### `users`
| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY | Auto-increment |
| `name` | TEXT UNIQUE NOT NULL | Login identifier (case-insensitive, stored lowercase) |
| `created_at` | TEXT | ISO 8601 timestamp |

### `daily_words`
| Column | Type | Notes |
|---|---|---|
| `date` | TEXT PRIMARY KEY | `YYYY-MM-DD` |
| `word` | TEXT NOT NULL | The day's word (lowercase) |
| `length` | INTEGER NOT NULL | 4–8 |

### `attempts`
| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY | Auto-increment |
| `user_id` | INTEGER NOT NULL | FK → `users.id` |
| `date` | TEXT NOT NULL | `YYYY-MM-DD` |
| `guesses` | TEXT | JSON array of guesses made (for replay/audit) |
| `num_guesses` | INTEGER NOT NULL | Number of guesses used (or max if failed/missed) |
| `solved` | INTEGER NOT NULL DEFAULT 0 | 1 = solved, 0 = failed or missed |
| `completed_at` | TEXT | ISO 8601 timestamp, NULL if missed |

**Unique constraint:** `(user_id, date)` — one attempt record per user per day.

---

## Daily Word Selection

Words are selected deterministically so all players get the same word:

1. **Word list**: A curated JSON file of common English words grouped by length (4–8), embedded in the Worker or stored in D1.
2. **Length for the day**: Derived from the date using a simple deterministic cycle or seeded PRNG:
   ```
   lengths = [4, 5, 6, 7, 8]
   dayIndex = daysSinceEpoch(date)
   todayLength = lengths[dayIndex % 5]
   ```
   This gives a rotating but unpredictable-feeling pattern.
3. **Word for the day**: Seeded selection from the word list for that length:
   ```
   words = wordsByLength[todayLength]
   wordIndex = seededHash(date) % words.length
   todayWord = words[wordIndex]
   ```
4. Words are lazily inserted into `daily_words` on first request of the day.

---

## API Endpoints (Pages Functions)

All endpoints live under `functions/api/`.

### `POST /api/login`
- **Body**: `{ "name": "mekhail" }`
- **Response**: `{ "userId": 1, "name": "mekhail" }`
- Creates user if not exists, returns existing user if name taken.
- Name stored lowercase, trimmed. Reject empty or names > 20 chars.

### `GET /api/today`
- **Response**: `{ "date": "2026-04-21", "wordLength": 6, "maxAttempts": 7 }`
- Does NOT reveal the word.

### `POST /api/guess`
- **Body**: `{ "userId": 1, "guess": "planet" }`
- **Validation**: Correct length, valid English word (checked against word list), user hasn't already completed today.
- **Response**:
  ```json
  {
    "result": [
      { "letter": "p", "status": "correct" },
      { "letter": "l", "status": "absent" },
      { "letter": "a", "status": "present" },
      { "letter": "n", "status": "correct" },
      { "letter": "e", "status": "absent" },
      { "letter": "t", "status": "correct" }
    ],
    "solved": false,
    "attemptsUsed": 3,
    "maxAttempts": 7,
    "guesses": [ ... ]  // all guesses so far with results
  }
  ```
- On solve or final failed attempt, writes the `attempts` record.

### `GET /api/leaderboard?date=2026-04-21`
- **Response**:
  ```json
  {
    "daily": [
      { "name": "mekhail", "numGuesses": 3, "solved": true },
      { "name": "alice", "numGuesses": 5, "solved": true },
      { "name": "bob", "numGuesses": 7, "solved": false }
    ],
    "monthly": [
      { "name": "mekhail", "totalGuesses": 45, "daysPlayed": 15 },
      { "name": "alice", "totalGuesses": 62, "daysPlayed": 18 }
    ]
  }
  ```
- **Daily**: Sorted by `num_guesses` ASC, solved first.
- **Monthly**: Sum of `num_guesses` for all days in the current month. Users who missed days get `max_attempts` for each missed day added via a scheduled fill or on-read calculation.

---

## Monthly Leaderboard — Missed Day Penalty

Two approaches (recommend Option B for simplicity on free tier):

**Option A — Cron backfill**: A Cloudflare Worker Cron Trigger runs daily at midnight UTC, inserts `attempts` rows for every user who didn't play yesterday with `num_guesses = max_attempts, solved = 0`.

**Option B — Calculate on read**: When querying the monthly leaderboard, compute missed-day penalties dynamically:
```sql
-- For each user, sum actual attempts + (missed_days × max_attempts_for_that_day)
```
This avoids needing cron and keeps the data clean. Since the user count and day count are small, this is fast enough.

---

## Frontend Design

### Pages

Flutter app with three screens managed by Navigator or a simple state-based approach:

1. **LoginScreen** — `TextField` for name, "Play" button.
2. **GameScreen** — Grid of `Container` tiles (rows = max attempts, cols = word length), on-screen keyboard widget with color state, guess input.
3. **LeaderboardScreen** — Shown after solving/failing. Two `DataTable`/`ListView` widgets side by side: today's results and monthly standings.

### UI Components

```
┌──────────────────────────────────┐
│  FuseIT Wordle    [Leaderboard]  │  ← Header
├──────────────────────────────────┤
│                                  │
│   ┌───┬───┬───┬───┬───┬───┐     │
│   │ P │ L │ A │ N │ E │ T │     │  ← Guess rows
│   └───┴───┴───┴───┴───┴───┘     │     (dynamic width based on word length)
│   ┌───┬───┬───┬───┬───┬───┐     │
│   │   │   │   │   │   │   │     │
│   └───┴───┴───┴───┴───┴───┘     │
│          ... more rows ...       │
│                                  │
│  ┌─────────────────────────────┐ │
│  │  Q W E R T Y U I O P       │ │  ← On-screen keyboard
│  │   A S D F G H J K L        │ │     (keys colored by status)
│  │  ⏎ Z X C V B N M ⌫        │ │
│  └─────────────────────────────┘ │
│                                  │
│  Attempt 3 of 7                  │  ← Status bar
└──────────────────────────────────┘
```

### Styling

- Dark theme (dark background, light text) — matches classic Wordle aesthetic.
- Tile colors: `#6aaa64` (green), `#c9b458` (yellow), `#3a3a3c` (grey), `#121213` (background).
- Responsive: works on mobile and desktop.
- Tile flip animation on reveal.
- Shake animation on invalid guess.

### State Management

- Use **Provider** or simple `StatefulWidget` + `ChangeNotifier` (no need for heavy state management for this scope).
- `userId` stored via `shared_preferences` (works on web — uses `localStorage` under the hood).
- Current game state (guesses so far) fetched from the API on app load if user has an in-progress game.
- API calls via `http` package.
- No client-side word validation beyond length — server is the authority.

---

## Project File Structure

```
FuseIT-Wordle/
├── .kiro/
│   └── design.md              ← This file
├── frontend/                  ← Flutter web app
│   ├── lib/
│   │   ├── main.dart          ← App entry point, routing
│   │   ├── screens/
│   │   │   ├── login_screen.dart
│   │   │   ├── game_screen.dart
│   │   │   └── leaderboard_screen.dart
│   │   ├── widgets/
│   │   │   ├── tile_grid.dart
│   │   │   ├── keyboard.dart
│   │   │   └── leaderboard_table.dart
│   │   ├── services/
│   │   │   └── api_service.dart   ← HTTP calls to Worker API
│   │   └── models/
│   │       ├── game_state.dart
│   │       └── leaderboard_entry.dart
│   ├── web/                   ← Flutter web shell (index.html etc.)
│   └── pubspec.yaml
├── functions/                 ← Cloudflare Pages Functions (Worker API)
│   └── api/
│       ├── login.js           ← POST /api/login
│       ├── today.js           ← GET /api/today
│       ├── guess.js           ← POST /api/guess
│       └── leaderboard.js     ← GET /api/leaderboard
├── src/
│   ├── words.js               ← Word lists by length (4–8)
│   ├── word-selection.js      ← Deterministic daily word logic
│   └── db.js                  ← D1 query helpers
├── migrations/
│   └── 0001_init.sql          ← D1 schema migration
├── wrangler.toml              ← Cloudflare config (Pages + D1 binding)
├── package.json               ← For wrangler/worker deps
└── README.md
```

---

## In-Progress Game State

Since the user might close the browser mid-game, we need to persist partial progress:

- **Option**: Store in-progress guesses in a `game_state` D1 table:
  | Column | Type |
  |---|---|
  | `user_id` | INTEGER |
  | `date` | TEXT |
  | `guesses` | TEXT (JSON) |

  This is queried on page load to restore the game. On completion (solve or fail), the row is used to write the final `attempts` record and then deleted.

---

## Deployment Steps

1. `npm create cloudflare@latest` — scaffold a Pages project (or manual setup).
2. Create D1 database: `npx wrangler d1 create fuseit-wordle-db`.
3. Add D1 binding in `wrangler.toml`.
4. Run migration: `npx wrangler d1 execute fuseit-wordle-db --file=migrations/0001_init.sql`.
5. Create Flutter project: `flutter create frontend` then enable web: `flutter config --enable-web`.
6. Build Flutter: `cd frontend && flutter build web --release`.
7. Configure `wrangler.toml` to point Pages at `frontend/build/web` as the output directory.
8. Develop locally: `npx wrangler pages dev frontend/build/web --d1=DB=fuseit-wordle-db`.
9. Deploy: `npx wrangler pages deploy frontend/build/web` or connect Git repo with a build command of `cd frontend && flutter build web --release`.

---

## Implementation Order

1. **Database**: Write migration SQL, create D1 database.
2. **Word selection**: Build word lists and deterministic selection logic.
3. **API — `/api/today`**: Return today's word length and max attempts.
4. **API — `/api/login`**: User creation/lookup.
5. **API — `/api/guess`**: Core game logic — validate guess, return letter statuses, track state.
6. **API — `/api/leaderboard`**: Daily + monthly leaderboard queries.
7. **Flutter — Project setup**: Create Flutter project, add dependencies (`http`, `shared_preferences`, `provider`).
8. **Flutter — LoginScreen**: Simple name input screen.
9. **Flutter — GameScreen**: Dynamic tile grid, keyboard widget, guess submission.
10. **Flutter — LeaderboardScreen**: Post-game display with both tables.
11. **Polish**: Tile flip/shake animations, responsive layout, edge cases.
12. **Deploy**: Build Flutter web, push to Cloudflare Pages.

---

## Edge Cases & Considerations

- **Duplicate letters in guess**: If the word is "APPLE" and the user guesses "PUPPY", handle duplicate P's correctly — only mark as many greens/yellows as there are occurrences in the answer.
- **Timezone**: Use UTC for day boundaries. Display local time to user but all server logic is UTC.
- **Name collisions**: Names are unique (case-insensitive). If "Mekhail" is taken, the user logs in as that user — this is by design (no password).
- **Word list size**: Aim for ~500+ words per length to avoid repetition for over a year.
- **Rate limiting**: Cloudflare's free tier has basic bot protection. No additional rate limiting needed for this scale.
- **Monthly rollover**: Monthly leaderboard resets on the 1st of each month (query filters by `YYYY-MM`).
