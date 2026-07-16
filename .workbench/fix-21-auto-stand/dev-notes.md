## Developer Notes — Auto-stand player on exactly 21 after hit

### Files Created
- none

### Files Modified
- `src/blackjack-mp-worker.js` — Added `else if (player.value === 21)` branch in `_handleHit` to auto-stand the player when they hit and reach exactly 21, broadcasting `player_stood` and advancing the turn via `nextTurn`.

### Key Decisions
- Used `player.status = 'stood'` and broadcast `player_stood` to mirror the existing stand flow, keeping client-side handling consistent.
- Called `nextTurn` after saving state, same as the bust path, so the next player immediately gets their turn.
- No other paths changed — hitting below 21 still leaves the player on their turn.

### Library Docs Consulted (Context7)
- none (pure JS logic, no third-party libraries touched)

### Build & Test Results
- Syntax check passed: `node --input-type=module --check < src/blackjack-mp-worker.js` → exit 0

### Open Issues
- none
## Developer Notes — Remove standalone ml fallback from generate-strands.mjs

### Files Created
- none

### Files Modified
- `scripts/generate-strands.mjs` — Removed the `if (Object.keys(scored).length < 15)` block (15 lines). This block injected ml word-vector results at score 1000 when tight sources returned fewer than 15 words. The loose associations (e.g. "pirates" via Jack Sparrow, "young" via sparrow biology) polluted grids. The ml-as-amplifier loop above it was left intact.

### Key Decisions
- Removed the fallback entirely rather than tightening its filters. Any score-1000 word is too likely to be thematically wrong; a failed theme is preferable to a bad grid.
- The ml amplifier (boosting words already present in `scored`) is correct behavior and was not touched.

### Library Docs Consulted (Context7)
- none — pure JavaScript removal, no third-party library involved.

### Build & Test Results
```
node --check scripts/generate-strands.mjs   → exit 0 (no syntax errors)
git commit b01c967 — 1 file changed, 15 deletions(-)
```

### Open Issues
- None. Themes with very few tight-source words will now simply fail to produce a grid (expected behavior).
