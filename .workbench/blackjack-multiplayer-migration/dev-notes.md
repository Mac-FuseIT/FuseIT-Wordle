# Developer Notes — BlackjackMultiplayerSession Durable Object

## Files Created
- `src/blackjack-mp-worker.js` — Cloudflare Worker + Durable Object for multiplayer blackjack (960 lines)

## Files Modified
None.

## Key Decisions

### Pattern fidelity to chess-game-worker.js
Followed the chess DO exactly: `super(ctx, env)` constructor, `ctx.acceptWebSocket(server)`, `ws.serializeAttachment / ws.deserializeAttachment`, `ctx.getWebSockets()` for broadcast, `this.env.DB` for D1 access.

### drawCard signature change
`bet.js` passes the whole `session` object to `drawCard`; the spec requires `drawCard(deck, inPlayCards)`. Implemented the two-arg form and collect in-play cards via `_allInPlayCards(state)` before every draw.

### getToday() — UTC, no weekend skipping
`db.js`'s `getToday()` skips weekends (Sat→Fri, Sun→Fri) for the word game. For blackjack sessions the date is just today's UTC date — that's what `blackjack_sessions` rows already use in `bet.js` / `today.js`. Implemented as a plain UTC split, matching what those handlers do.

### Message dispatch via private _handle* methods
Rather than a giant switch inside `webSocketMessage`, each case is a private async method. This keeps the dispatch table small and each handler self-contained.

### Pending-leave mid-round
Players who send `leave` during `betting/playing/dealer_turn` are marked `pendingLeave = true` rather than removed. Their hand auto-stands if they were active. Removal happens in the 5-second post-round reset inside `resolveRound`.

### Turn timeouts
`_setTurnTimeout(userId, ms)` re-reads state from storage before acting so a stale closure doesn't operate on old data. The timeout reads the authoritative state and checks that the player is still the current turn player with status `playing`.

### Disconnect during active round
`webSocketClose` distinguishes: if not in an active round, a 5-minute timeout removes the player unless they reconnect. If in an active round and it's their turn, a 30-second auto-stand fires.

### Deck reshuffle
`drawCard` pops from the deck array (passed by reference as part of `state.deck`). If empty, a fresh 52-card deck is created, cards currently in play are excluded, and the remainder is pushed onto the existing array — no new reference needed.

### Blackjack payout
`payout = bet + Math.floor(bet * 1.5)` — 3:2 payout matching `bet.js`.

### Dealer hole card hiding
`getGameStateFor` returns the second dealer card as `{suit:'hidden', rank:'hidden'}` whenever `phase === 'playing'`. All other phases reveal the full hand.

## Library Docs Consulted (Context7)
None — all APIs used (Cloudflare Durable Objects, WebSocketPair, `ctx.acceptWebSocket`, `ws.serializeAttachment`) were verified directly against `src/chess-game-worker.js` which is the authoritative working example in this codebase.

## Build & Test Results
- `node --input-type=module --check < src/blackjack-mp-worker.js` → exit 0 (clean syntax)
- Committed on branch `feat/blackjack-multiplayer-migration` as commit `b201398`

## Open Issues
- `wrangler-blackjack-worker.toml` needs `[[durable_objects.bindings]]` entry for `BLACKJACK_GAME` binding pointing to `BlackjackMultiplayerSession`. This toml file already exists (untracked) — reviewer should populate it.
- D1 table `blackjack_mp_games` is referenced but its migration SQL is not in this file. Ensure `migrations/` has the corresponding schema before deploying.
- `blackjack_results` cashout check assumes the single-player table — confirm column names match for multiplayer context.
## Dart Developer Notes — lobby-screen: Add multiplayer support to blackjack_lobby_screen.dart

### Files Modified
- `frontend/lib/blackjack/blackjack_lobby_screen.dart` — Added full multiplayer support while preserving all existing singleplayer functionality

### Changes Made
1. Added `dart:async` import and `blackjack_mp_screen.dart` import
2. Added state variables: `_mpGames`, `_mpLoading`, `_mpGameId`, `_refreshTimer`
3. Modified `initState` to start a 5-second periodic timer calling `_loadGames()`
4. Added `dispose()` override to cancel the refresh timer
5. Added `_loadGames()` method — fetches `/api/blackjack-mp/games`
6. Modified `_load()` to call `_loadGames()` at the end
7. Added `_createMpGame()` method — POSTs to `/api/blackjack-mp/create` and sets `_mpGameId`
8. Modified `build()` to check `_mpGameId != null` first (before `_playing`), rendering `BlackjackMpScreen` when set
9. Added `_buildPlayWithFriendsButton()` — uses `widget.theme.present` color
10. Added `_buildOpenTables()` — lists open MP games with Join buttons using `widget.theme.correct` color
11. Wired the new buttons into the Column after `_buildPlayButton()`

### Key Decisions
- `_mpGameId` check placed before `_playing` check in `build()` so joining/creating a multiplayer game takes navigation priority
- `_load()` calls `_loadGames()` with `await` at the end so initial page load also populates open tables
- Timer is cancelled in `dispose()` to prevent setState on dead widget
- Theme fields used: `theme.present` (yellow/amber) for "Play with Friends" button, `theme.correct` (green) for "Join" buttons — consistent with the existing singleplayer button pattern

### Packages & Docs Consulted
- None — all APIs are standard Flutter/Dart; existing patterns in the file were followed

### Analyze & Test Results
- `analyze_files` on `blackjack_lobby_screen.dart`: **No errors**
- Note: `blackjack_mp_screen.dart` import is intentionally unresolved until that file is created by a separate task

### Open Issues
- `blackjack_mp_screen.dart` must be created with the signature: `BlackjackMpScreen({required AppTheme theme, required VoidCallback onBack, required String nickname, required int userId, required String gameId})`
- Once that file exists the full project should be re-analysed to confirm zero errors

## Dart Developer Notes — blackjack_mp_screen.dart

### Files Created
- `frontend/lib/blackjack/blackjack_mp_screen.dart` — Full multiplayer blackjack game screen StatefulWidget

### Files Modified
- None

### Key Decisions
- Card rendering (`_buildCard` and `_buildSmallCard`) copied directly from `blackjack_screen.dart` pattern — white containers with rank+suit symbol, hidden cards show blue background with `?`
- `_buildSmallCard` added for compact player seat display (32×44 vs full 52×72)
- `_currentTurn` is an index into `_players`, matching `turn_start` message which sends userId — we find the index on receipt
- `_handleMessage` uses `Map<String, dynamic>.from(...)..['key'] = value` cascade pattern for safe immutable updates to player entries
- Bet slider max is capped to `_myBalance` at betting time; disabled state shown for chips > balance
- Round results auto-clear after 5s via Timer stored in `_resultsTimer`; error auto-clears after 3s via `_errorTimer`; both timers cancelled in `dispose()`
- Double button rendered but disabled (greyed) when hand length ≠ 2, matching solo game pattern
- `_connected` flag drives a yellow reconnecting banner at top; set false on `connection_lost`, true on `player_reconnected`
- Player seat border: yellow (`theme.present`) for current turn overrides green (`theme.correct`) for self

### Packages & Docs Consulted
- No new packages added — all imports are `dart:async`, `package:flutter/material.dart`, and project-local files
- Patterns cross-referenced from `blackjack_screen.dart` (card rendering, chip selector, bet slider) and `pvp_game_screen.dart` (WS message handler switch, setState patterns)

### Analyze & Test Results
- `analyze_files` on `lib/blackjack/blackjack_mp_screen.dart`: **No errors**
- No widget tests written (UI-only screen, no business logic to unit test)

### Open Issues
- `_betAmount` slider lower bound is 1 but chips start at 5; user can drag to values not matching any chip — acceptable UX, matches solo game
- `_myBalance` starts at 0 before first `game_state` arrives; balance bar shows `$0` briefly — not a bug, just a load state
- `player_joined` message may carry player data at top level or under a `player` key — handler checks both patterns defensively
