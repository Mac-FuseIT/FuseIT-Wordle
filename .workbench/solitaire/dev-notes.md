## Developer Notes — solitaire migration (0021_solitaire.sql)

### Files Created
- `migrations/0021_solitaire.sql` — Creates `solitaire_sessions` and `solitaire_results` tables with appropriate indexes

### Files Modified
- none

### Key Decisions
- File created exactly as specified, no modifications
- `solitaire_sessions` stores per-user per-day game state as JSON blob in `session_state`
- `solitaire_results` stores final outcome (completed, moves, time, points) with a unique constraint per user+date
- Two indexes on `solitaire_results` for efficient leaderboard queries by date and by user+date

### Library Docs Consulted (Context7)
- none (pure SQL migration, no third-party libraries)

### Build & Test Results
- File created and committed successfully on branch `feat/solitaire`

### Open Issues
- none
## Developer Notes — Deterministic deck generation (Task 1)

### Files Created
- `src/solitaire-deck.js` — Seeded PRNG (mulberry32), date-to-seed hash, Fisher-Yates shuffle, and Klondike deal layout. Exports `mulberry32`, `dateToSeed`, `generateDeck`, `dealGame`.

### Files Modified
None.

### Key Decisions
- Implemented exactly as specified in the spec — no deviations.
- Card encoding: `{rank}{suit}` (e.g. `"10h"`, `"Kd"`), suits lowercase single char.
- Deal layout: 7 tableau columns (col 0 = 1 card, col 6 = 7 cards), 28 total dealt, 24 to stock.
- `drawPointer: 0` initialised in `dealGame` for draw-3 cycling state.
- Named ES module exports (`export { ... }`) for compatibility with Cloudflare Pages Functions.

### Library Docs Consulted (Context7)
None — no third-party libraries touched.

### Build & Test Results
File created and committed. No build step required for a pure JS utility module.

### Open Issues
None — file matches spec exactly.

## Developer Notes — draw endpoint

### Files Created
- `functions/api/solitaire/draw.js` — POST handler that draws up to 3 cards from the stock pile onto the waste pile, increments move counter, and persists updated session state to D1.

### Files Modified
None.

### Key Decisions
- Used `state.stock.splice(-Math.min(3, state.stock.length))` to draw from the top (end) of the stock array — consistent with a stack representation where the last element is the top card.
- Returns `waste_top` as `state.waste.slice(-3)` so the client gets the visible fan of up to 3 waste cards.
- `started_at` is set lazily on first action (same pattern as other solitaire endpoints).
- Stock-empty guard returns a descriptive error pointing the user toward the recycle action.

### Library Docs Consulted (Context7)
None — no third-party libraries touched; uses only project-internal helpers from `src/db.js` and Cloudflare D1 bindings.

### Build & Test Results
No build step required for Cloudflare Pages Functions (plain JS). File committed cleanly on `feat/solitaire`.

### Open Issues
None.

## Developer Notes — recycle endpoint

### Files Created
- `functions/api/solitaire/recycle.js` — POST handler that flips the waste pile back into the stock when the stock is empty.

### Files Modified
None.

### Key Decisions
- Guards: requires stock empty AND waste non-empty; rejects if game is already over.
- `state.waste.reverse()` flips order so the card that was last drawn becomes the new bottom of stock (correct Klondike behaviour).
- `started_at` set lazily on first action, consistent with other solitaire endpoints.
- Returns `waste_top: null` and `waste_count: 0` since waste is cleared after the flip.

### Library Docs Consulted (Context7)
None — no third-party libraries touched.

### Build & Test Results
File created and committed on `feat/solitaire` (commit d089099).

### Open Issues
None.

## Developer Notes — GET /api/solitaire/today endpoint

### Files Created
- `functions/api/solitaire/today.js` — GET endpoint that returns today's solitaire game state (or creates one if none exists). Also exports `onRequestOptions` for CORS preflight handling.

### Files Modified
- None

### Key Decisions
- Matches the exact code provided in the task spec verbatim — no deviations needed.
- If a `solitaire_results` row exists for today, returns completed state (won/gave_up) with no game board data.
- If no session exists, calls `dealGame(today)` from `src/solitaire-deck.js` and inserts a new row.
- Hidden cards are never sent to the client — only counts are returned.
- `elapsed_seconds` is 0 when `started_at` is null (timer not yet started).
- `waste_top` returns up to 3 most-recently-drawn cards (slice(-3)), empty array when waste is empty.

### Library Docs Consulted (Context7)
- None — no third-party libraries used. All imports are local project modules.

### Build & Test Results
- No build step required for Cloudflare Pages Functions (plain ESM JS).
- File committed to `feat/solitaire` at `7f4717e`.

### Open Issues
- None. Endpoint is straightforward — depends on `src/solitaire-deck.js` (already present) and `solitaire_sessions`/`solitaire_results` tables (schema in `migrations/0021_solitaire.sql`).

## Developer Notes — give-up endpoint

### Files Created
- `functions/api/solitaire/give-up.js` — POST endpoint to voluntarily end a solitaire game; marks session status as `gave_up`, records 1 point in `solitaire_results`

### Files Modified
None.

### Key Decisions
- Used `INSERT OR IGNORE` to avoid duplicate result rows if the endpoint is called more than once (idempotent-safe).
- Time is calculated from `started_at` stored in the session row; falls back to 0 if absent.
- Moves count is read from the current in-memory state, consistent with how other endpoints track it.

### Library Docs Consulted (Context7)
None — no third-party libraries touched; purely Cloudflare Pages Functions / D1 patterns already established in the project.

### Build & Test Results
No build step required for Cloudflare Pages Functions JS files. File created and committed cleanly.

### Open Issues
None.

## Developer Notes — solitaire leaderboard endpoint

### Files Created
- `functions/api/solitaire/leaderboard.js` — GET /api/solitaire/leaderboard; returns daily and monthly leaderboards from `solitaire_results`, requires auth

### Files Modified
- none

### Key Decisions
- Daily board orders by `points DESC, time_seconds ASC` (higher score wins, ties broken by faster time)
- Monthly board aggregates `SUM(points)`, `COUNT(*)`, `SUM(completed)` grouped by `user_id`, ordered by total points then wins
- Both queries capped at 50 rows
- CORS OPTIONS handler included consistent with other solitaire endpoints

### Library Docs Consulted (Context7)
- none (no third-party libraries touched)

### Build & Test Results
- File created, committed to `feat/solitaire` (commit 46cfa14)
- No build step available for plain JS Cloudflare Pages Functions

### Open Issues
- none

## Developer Notes — move endpoint (Task 4)

### Files Created
- `functions/api/solitaire/move.js` — POST /api/solitaire/move; validates and applies card moves, runs auto-move logic, detects win, persists state

### Files Modified
None.

### Key Decisions
- Implements all move types from spec: waste→tableau, waste→foundation, tableau→tableau, tableau→foundation, foundation→tableau
- Source extraction handles `cardIndex` defaulting to top of visible stack; slices entire sub-stack for tableau→tableau moves
- Tableau destination validation: empty column accepts only Kings; non-empty column requires one rank lower + opposite colour
- Foundation validation: empty pile accepts only Ace; non-empty requires same suit and exactly next rank
- `splice(cardIndex)` removes cards from source tableau column starting at the picked index (removes picked card and everything above)
- Auto-move loop restarts from scratch after each auto-move (breaks inner for-loop and re-enters while) to catch chains (e.g. moving 2 exposes another Ace)
- Win check runs after auto-move so auto-moved cards count toward the 52-card total
- `INSERT OR IGNORE` on `solitaire_results` prevents duplicate records if win is somehow detected twice
- `started_at` set lazily on first action, consistent with all other solitaire endpoints
- CORS OPTIONS handler included

### Library Docs Consulted (Context7)
None — no third-party libraries touched.

### Build & Test Results
File created (269 lines) and committed to `feat/solitaire` (commit 6caeb5d).

### Open Issues
None.
