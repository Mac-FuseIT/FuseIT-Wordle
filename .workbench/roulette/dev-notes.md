## Developer Notes — Create roulette_results migration

### Files Created
- `migrations/0020_roulette.sql` — D1 migration that creates the `roulette_results` table and two indexes

### Files Modified
_none_

### Key Decisions
- Exact SQL provided by the task — no alterations made.
- `UNIQUE(user_id, date)` enforces one row per user per day (upsert-friendly).
- Two indexes: one on `date` for leaderboard queries, one composite on `(user_id, date)` for per-user lookups.

### Library Docs Consulted (Context7)
none — pure SQL migration, no third-party library touched.

### Build & Test Results
File created and committed cleanly on branch `feat/roulette`.

### Open Issues
_none_

## Developer Notes — status Pages Function

### Files Created
- `functions/api/roulette/status.js` — Cloudflare Pages Function that authenticates the request via `requireAuth`, then proxies a GET to the `ROULETTE_TABLE` Durable Object's `/status` endpoint. Falls back to an idle state object on error.

### Files Modified
None.

### Key Decisions
- Exact file content provided by supervisor — no design decisions required.
- Error fallback returns `{ players: [], phase: 'idle', roundNumber: 0 }` so the client always gets a valid shape even if the DO is unavailable.

### Library Docs Consulted (Context7)
None — no third-party libraries touched; only project-internal helpers from `src/db.js`.

### Build & Test Results
No build step required for a plain JS Pages Function. File committed cleanly.

### Open Issues
None.

## Developer Notes — RouletteTable Durable Object (src/roulette-worker.js)

### Files Created
- `src/roulette-worker.js` — Full Cloudflare Worker with `RouletteTable` Durable Object and default fetch handler

### Files Modified
- None

### Key Decisions

**`broadcast(data, excludeWs)` signature** — Added an optional `excludeWs` parameter so the `_handleJoin` method can broadcast `player_joined` to all *other* players while sending a richer `game_state` snapshot only to the joiner. The blackjack reference used a separate `sendTo` helper; this is cleaner for roulette's simpler protocol.

**`transitionToBetting` called from `_handleJoin`** — When the first player joins an idle table, `transitionToBetting` is called directly (it saves state itself), so we `return` early rather than calling `saveState` again to avoid a double-write.

**`player.balance` cache in DO state** — Balance is cached on the player object in DO state for the `game_state` snapshot, but a fresh D1 read is always done in `getGameState`, `_handlePlaceBet`, and `transitionToResult`. This mirrors the blackjack MP pattern exactly.

**`webSocketClose` vs `_handleLeave`** — Both paths do the same teardown. They're separate because `webSocketClose` fires on unexpected disconnects while `leave` is intentional. Both remove the player and stop the alarm if no players remain.

**`ON CONFLICT ... DO UPDATE` for roulette_results** — Uses SQLite upsert syntax to increment stats atomically, avoiding a separate read-then-write. This matches what the spec calls an "upsert".

**Payout for straight bet** — `amount * 35 + amount = amount * 36`. The +amount is the original stake returned. This correctly implements 35:1 payout odds.

**0 does not count for even/odd/high/low** — All four even-money bet handlers check `winningNumber > 0` (odd/even) or `winningNumber >= 1` (low) / `winningNumber >= 19` (high) so zero pays nothing on those bets, matching European roulette rules.

**Alarm stops when table empties** — Both `_handleLeave` and `webSocketClose` call `this.ctx.storage.deleteAlarm()` when `state.players.length === 0`. The loop restarts on the next player's `join`.

### Library Docs Consulted (Context7)
None — no third-party libraries. All APIs are Cloudflare Workers builtins (`DurableObject`, `WebSocketPair`, `ctx.storage`, `ctx.getWebSockets()`) and standard D1 SQL.

### Build & Test Results
```
$ node --input-type=module --check < src/roulette-worker.js
(exit 0 — no syntax errors)
```

### Open Issues
- `wrangler-roulette-worker.toml` exists (untracked) but was not reviewed in this sub-task — confirm it references the correct D1 database ID and DO class name `RouletteTable` before deploying.
- `migrations/0020_roulette.sql` needs to be created and run before deploying (creates `roulette_results` table).
- `functions/api/roulette/status.js` Pages Function (proxy to worker `/status`) not yet created.

## Dart Developer Notes — roulette_state.dart constants and helpers

### Files Created
- `frontend/lib/blackjack/roulette/models/roulette_state.dart` — European roulette constants (`redNumbers`, `wheelOrder`, `payoutMultipliers`) and `getNumberColor` helper

### Files Modified
- none

### Key Decisions
- Pure constants and a single pure function — no imports needed; file is self-contained
- Used `const` for all collections so they are compile-time constants, zero runtime cost
- `getNumberColor` returns `String` literals (`'green'`, `'red'`, `'black'`) matching the spec exactly

### Packages & Docs Consulted
- none — no third-party packages touched

### Analyze & Test Results
- `analyze_files` → No errors

### Open Issues
- none

## Dart Developer Notes — RouletteWebSocket creation

### Files Created
- `frontend/lib/blackjack/roulette/roulette_websocket.dart` — WebSocket client for roulette multiplayer. Mirrors `BlackjackMpWebSocket` pattern: auto-reconnect on unexpected disconnect, `onMessage` callback, typed send helpers (`placeBet`, `clearBets`, `leave`, `dispose`).

### Files Modified
- None

### Key Decisions
- Mirrored `blackjack_mp_websocket.dart` exactly but stripped the `gameId` param (roulette has a single shared room at `/api/roulette/join`).
- Added explicit `as Map<String, dynamic>` cast on `jsonDecode` result to keep analyzer happy without using `dynamic`.
- Kept debug `print` calls out — the provided spec snippet had no prints, and the roulette WS is simpler than blackjack-mp.

### Packages & Docs Consulted
- No new packages. `web_socket_channel` already in project dependencies.

### Analyze & Test Results
- `analyze_files` on `roulette_websocket.dart` → **No errors**

### Open Issues
- None

## Dart Developer Notes — CasinoLobbyScreen (lobby-toggle)

### Files Created
- `frontend/lib/blackjack/roulette/roulette_screen.dart` — Minimal stub (`RouletteScreen`) so the import resolves. Full implementation is a separate task.

### Files Modified
- `frontend/lib/blackjack/blackjack_lobby_screen.dart` — Renamed `BlackjackLobbyScreen` → `CasinoLobbyScreen`. Added Blackjack/Roulette tab toggle, roulette state fields (`_selectedTab`, `_roulettePlayers`, `_roulettePhase`, `_playingRoulette`), roulette status polling in `_loadGames()`, `_buildToggle()` / `_buildToggleButton()` widgets, `_buildRouletteSection()`, title changed to 'Casino', `RouletteScreen` shown when `_playingRoulette` is true.

### Key Decisions
- Kept filename `blackjack_lobby_screen.dart` as-is; `main.dart` already had the import pointing there and was already using `CasinoLobbyScreen` as the class name.
- `_roulettePhase` is stored in state even though not yet displayed, so it's available for future use (e.g., disabling "Join" during SPINNING/RESULT).
- Toggle style matches the spec exactly: `withOpacity(0.2)` background + solid border on selected, transparent + grey border on unselected — same visual language as `_buildTab` in the leaderboard section.

### Packages & Docs Consulted
- No new packages. `http`, `dart:convert`, `shared_preferences` already in project.

### Analyze & Test Results
- `analyze_files` on both modified/created files → **No errors**

### Open Issues
- `RouletteScreen` stub returns "Coming soon…". Replace with real implementation when the roulette screen task runs.
- `_roulettePhase` is fetched but not yet used to disable the Join button mid-round — can be wired up when `RouletteScreen` is live.
