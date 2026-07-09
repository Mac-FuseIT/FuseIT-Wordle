## Developer Notes — blackjack-mp create game endpoint

### Files Created
- `functions/api/blackjack-mp/create.js` — POST endpoint that authenticates the user, ensures a solo blackjack session exists for today, generates a UUID game ID, and inserts a new `blackjack_mp_games` row with status `waiting`.

### Files Modified
- none

### Key Decisions
- Followed the session-creation pattern from `functions/api/blackjack/today.js` exactly.
- `defaultSession` in create.js uses empty `deck: []` (deck initialised lazily when game starts) — consistent with spec provided.
- Used `crypto.randomUUID()` (available natively in Cloudflare Workers) for game ID generation.

### Library Docs Consulted (Context7)
- none — no third-party libraries touched; Cloudflare Workers built-ins only.

### Build & Test Results
- No build step required for plain JS Cloudflare Pages Functions.
- No existing test suite to run.

### Open Issues
- none
