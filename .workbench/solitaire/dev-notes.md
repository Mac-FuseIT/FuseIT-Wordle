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