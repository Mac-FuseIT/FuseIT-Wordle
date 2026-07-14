# Task: Implement Roulette (Spin.IT) for Fuse Arcade

## User Request
Implement a European Roulette multiplayer game ("Spin.IT") that lives in the existing blackjack lobby (renamed to "Casino" lobby). Single persistent table, shared $100 daily balance with blackjack, real-time multiplayer via WebSocket, animated wheel, combined leaderboard.

## Codebase Summary
- **Stack**: Cloudflare Workers + Durable Objects (JS), Cloudflare Pages Functions (JS), Flutter Web (Dart), D1 SQLite database
- **Structure**:
  - `src/` — Worker scripts (blackjack-mp-worker.js, chess-worker.js etc.)
  - `functions/api/` — Pages Functions (REST endpoints)
  - `frontend/lib/` — Flutter app (screens, widgets, services, models)
  - `migrations/` — D1 SQL migrations (currently up to 0019)
  - `wrangler-*.toml` — Per-worker Cloudflare configs
- **Conventions**:
  - Workers: Single JS file with `DurableObject` class extending `cloudflare:workers`, WebSocket via `WebSocketPair`, `ctx.acceptWebSocket()`, `ws.serializeAttachment()` for session data, `this.ctx.storage.get/put` for DO state
  - D1 access: `this.env.DB.prepare(...).bind(...).first()/run()/all()`
  - Balance: Read from `blackjack_sessions.session_state` (JSON with `balance` field), deduct on bet, credit on win
  - Date logic: `getToday()` function maps Sat→Fri, Sun→Fri
  - Frontend WS: `WebSocketChannel.connect()`, auto-reconnect on close, `serializeAttachment` pattern, send `join` on connect
  - Frontend screens: `StatefulWidget`, `AppTheme` prop, `onBack` callback, max-width 500px `ConstrainedBox`
  - Lobby pattern: Status card + action buttons + leaderboard, periodic polling with `Timer.periodic`
  - Navigation: `AppView` enum in `main.dart`, lobby screen launched via switch expression
- **Critical Findings**: None — all patterns are well-established and the spec aligns with existing architecture.

## Relevant Files

### Backend References
| File | Why |
|------|-----|
| `src/blackjack-mp-worker.js` | DO pattern: WebSocket upgrade, message routing, D1 balance read/write, broadcast helper, state get/save |
| `wrangler-blackjack-worker.toml` | Worker config template (D1 binding, DO binding, migration tag) |
| `functions/api/blackjack/leaderboard.js` | Current leaderboard query — needs updating to include roulette stats |
| `migrations/0019_blackjack_multiplayer.sql` | Migration format reference |
| `src/db.js` | Shared helpers: `getToday()`, `jsonResponse()`, `errorResponse()`, `requireAuth()` |

### Frontend References
| File | Why |
|------|-----|
| `frontend/lib/blackjack/blackjack_lobby_screen.dart` | Current lobby — will be renamed/expanded to Casino lobby |
| `frontend/lib/blackjack/blackjack_mp_websocket.dart` | WebSocket client pattern (connect, reconnect, send, dispose) |
| `frontend/lib/blackjack/blackjack_mp_screen.dart` | Multiplayer screen structure reference |
| `frontend/lib/chess/chess_lobby_screen.dart` | Toggle UI pattern (Normal/Phantom game cards side-by-side) |
| `frontend/lib/main.dart` | Navigation — references `BlackjackLobbyScreen` at line 179 |

## Execution Plan

### Wave 1: Config & Schema
| Sub-task | Agent | Files | Details |
|----------|-------|-------|---------|
| Create wrangler config | developer | `wrangler-roulette-worker.toml` | Copy pattern from `wrangler-blackjack-worker.toml`. Name: `fuseit-roulette-worker`, main: `src/roulette-worker.js`, same D1 binding, DO binding `ROULETTE_TABLE` → class `RouletteTable`, migration tag v1 with `new_sqlite_classes: ["RouletteTable"]` |
| Create D1 migration | developer | `migrations/0020_roulette.sql` | Create `roulette_results` table with columns: `id` (PK autoincrement), `user_id` (INT NOT NULL), `date` (TEXT NOT NULL), `spins_played` (INT DEFAULT 0), `total_wagered` (INT DEFAULT 0), `total_won` (INT DEFAULT 0), `net_profit` (INT DEFAULT 0), `updated_at` (TEXT DEFAULT datetime('now')), UNIQUE(user_id, date). Add indexes on `date` and `(user_id, date)`. |

### Wave 2: Backend — Roulette Worker
| Sub-task | Agent | Files | Details |
|----------|-------|-------|---------|
| Implement RouletteTable Durable Object | developer | `src/roulette-worker.js` | Full implementation including: **1)** `RouletteTable` class extending `DurableObject` with state machine (betting/spinning/result phases). **2)** Alarm-based loop: `alarm()` method transitions phases — betting(20s) → spinning(5s) → result(5s) → betting. Loop starts on first player connect, stops when last player leaves. **3)** WebSocket handling: `fetch()` for WS upgrade (path `/join`) and HTTP GET (path `/status`). `webSocketMessage()` routing for `join`, `place_bet`, `clear_bets`, `leave`. **4)** `_handleJoin`: Read balance from `blackjack_sessions` (or create default $100 session). Check cashout status from `blackjack_results`. If cashed out, mark as spectator. Send `game_state` snapshot. Broadcast `player_joined`. Start loop if first player. **5)** `_handlePlaceBet`: Validate phase is betting, validate balance (fresh D1 read), deduct from `blackjack_sessions`, store bet in DO state, broadcast `bet_placed`. **6)** `_handleClearBets`: Refund all bets (credit back to `blackjack_sessions`), clear player's bets in DO state, broadcast `bets_cleared`. **7)** `transitionToSpinning`: Generate winning number (0-36 via `Math.random`), determine color (red/black/green), broadcast `spinning` message with winning number + color. **8)** `transitionToResult`: Calculate payouts per player per bet (straight=35:1, red/black/odd/even/high/low=1:1). Credit winnings to `blackjack_sessions`. Upsert `roulette_results` (increment spins_played, total_wagered, total_won, net_profit). Broadcast `result` with payouts. **9)** `transitionToBetting`: Clear all bets, increment round number, broadcast `betting` with timeRemaining. **10)** `webSocketClose`: Remove player, if last player and no active bets then stop alarm loop. **11)** `broadcast(msg)`: Iterate `this.ctx.getWebSockets()` and send JSON. **12)** `getToday()` helper (same Sat→Fri, Sun→Fri logic). **13)** Default export: route `/join` to DO (keyed `"roulette-main"`), route `/status` to DO's HTTP handler. |
| Create Pages Function for status | developer | `functions/api/roulette/status.js` | GET endpoint. Fetch the roulette worker URL (env var `ROULETTE_WORKER_URL` or hardcoded worker domain) at path `/status`. Forward response. Include CORS `onRequestOptions` handler. Import `requireAuth` from `src/db.js` for auth check. |

### Wave 3: Frontend — WebSocket Client & Data Models
| Sub-task | Agent | Files | Details |
|----------|-------|-------|---------|
| Create roulette data models | dart-developer | `frontend/lib/blackjack/roulette/models/roulette_state.dart` | Data classes: `RouletteBet` (betType, betValue, amount), `RoulettePlayer` (userId, name, bets list), `RouletteGameState` (phase, timeRemaining, players, yourBalance, yourBets, lastResult, history, roundNumber). Include a `RouletteResult` class (winningNumber, winningColor, payouts). Add bet type constants and payout multipliers. Add `redNumbers` set and `getColor(int number)` helper. |
| Create roulette WebSocket client | dart-developer | `frontend/lib/blackjack/roulette/roulette_websocket.dart` | Mirror `blackjack_mp_websocket.dart` pattern. Connect to `wss://{host}/api/roulette/join`. Auto-send `join` message with userId and name on connect. Auto-reconnect on close (2s delay). Methods: `connect(userId, name)`, `placeBet(betType, betValue, amount)`, `clearBets()`, `leave()`, `dispose()`. Callback: `onMessage(Map<String, dynamic>)`. Use `_intentionallyClosed` flag pattern. |

### Wave 4: Frontend — Casino Lobby + Roulette Screen
| Sub-task | Agent | Files | Details |
|----------|-------|-------|---------|
| Rename lobby to Casino + add toggle | dart-developer | `frontend/lib/blackjack/blackjack_lobby_screen.dart` | **Rename class** `BlackjackLobbyScreen` → `CasinoLobbyScreen` (keep same file for now — rename file is risky with imports). **Add state**: `_selectedTab` (0=blackjack, 1=roulette), `_roulettePlayers` list, `_roulettePhase` string. **Add roulette polling**: In `_refreshTimer`, also call `GET /api/roulette/status` to update `_roulettePlayers` and `_roulettePhase`. **Update title** from 'Stack.IT' to 'Casino'. **Add toggle row** below status card: Two pill-shaped buttons `[ Blackjack ]` `[ Roulette ]` with highlighted state (use `Container` with rounded border + filled background when selected, similar to chess lobby game cards). **When Blackjack selected**: Show existing Play Solo, Play with Friends, Open Tables (unchanged). **When Roulette selected**: Show "Join Roulette Table" button (disabled if cashed out, same pattern as existing), show player list from `_roulettePlayers` with green dots, or "Table is empty" message. **Add `_playingRoulette` state** — when true, render `RouletteScreen`. **Keep leaderboard always visible** below toggle content. |
| Update main.dart navigation | dart-developer | `frontend/lib/main.dart` | Change `BlackjackLobbyScreen` import and reference to `CasinoLobbyScreen`. Keep the same `AppView.blackjackGame` enum value (just point to renamed class). |
| Create roulette game screen | dart-developer | `frontend/lib/blackjack/roulette/roulette_screen.dart` | Main game screen widget. **Layout** (Column in SingleChildScrollView): Header row (back button, "Roulette" title, balance display), RouletteWheel widget, phase timer bar (LinearProgressIndicator with countdown), BettingTable widget, bet summary section (list your bets + total + "Clear All" button), player list section (other players' names + total bets). **State management**: Connect `RouletteWebSocket` in `initState`, parse messages to update `RouletteGameState`, dispose WS in `dispose`. **Phase handling**: On `game_state` → initialize all state. On `betting` → reset bets, start timer countdown. On `spinning` → pass winningNumber to wheel, disable betting table. On `result` → show payouts, update balance. On `bet_placed` → update player bets display. On `error` → show SnackBar. **Props**: theme, onBack, nickname, userId. |

### Wave 5: Frontend — Wheel Animation & Betting Table Widgets
| Sub-task | Agent | Files | Details |
|----------|-------|-------|---------|
| Create roulette wheel widget | dart-developer | `frontend/lib/blackjack/roulette/widgets/roulette_wheel.dart` | `RouletteWheel` StatefulWidget. Props: `winningNumber` (nullable), `phase` (string), `onSpinComplete` callback. **CustomPainter**: Draw 37 arcs (European wheel order: [0,32,15,19,4,21,2,25,17,34,6,27,13,36,11,30,8,23,10,5,24,16,33,1,20,14,31,9,22,18,29,7,28,12,35,3,26]). Color each arc (green for 0, red/black per standard). Draw number text on each arc. Draw ball pointer (triangle) at top. **Animation**: `AnimationController` with 4s duration + `Curves.easeOutCubic`. When `winningNumber` changes and phase is 'spinning', calculate target angle (find pocket index in wheel order, multiply by 2π/37, add full rotations for visual effect). Animate from current angle to target. Wrap in `RepaintBoundary`. **Result state**: When phase is 'result', add glow/pulse on winning pocket (use `AnimationController` for opacity pulse). Size: 220x220 in a centered Container. |
| Create betting table widget | dart-developer | `frontend/lib/blackjack/roulette/widgets/betting_table.dart` | `BettingTable` StatefulWidget. Props: `enabled` (bool — false during spinning/result), `onBetPlaced(betType, betValue, amount)` callback, `currentBets` (list), `otherPlayerBets` (map). **Layout**: Column of Rows. Row 1: [0] spanning full width (green). Rows 2-13: 3 numbers per row [1,2,3], [4,5,6]...[34,35,36] with red/black coloring. Bottom rows: [RED][BLACK], [ODD][EVEN], [LOW 1-18][HIGH 19-36]. **Tap behavior**: On tap of any cell, show chip amount selector overlay (row of buttons: $1, $5, $10, $25 — or max). On amount select, call `onBetPlaced`. **Visual**: Show small chip icon on cells that have bets. Show dimmer/smaller chips for other players' bets. Each cell is a `GestureDetector` wrapping a colored `Container` with number text. Disable taps when `enabled` is false (grey overlay). |
| Create chip selector & phase timer | dart-developer | `frontend/lib/blackjack/roulette/widgets/bet_chips.dart`, `frontend/lib/blackjack/roulette/widgets/phase_timer.dart` | **bet_chips.dart**: `ChipSelector` widget — horizontal row of chip buttons ($1, $5, $10, $25). On tap, calls `onAmountSelected(int)`. Highlighted chip = last selected amount (persists between bets). **phase_timer.dart**: `PhaseTimer` widget. Props: `phase` (string), `totalDuration` (ms), `timeRemaining` (ms). Shows a `LinearProgressIndicator` with label ("Betting: 14s", "Spinning...", "Results"). Color: green during betting, yellow during spinning, blue during result. Uses `Timer.periodic(1s)` to count down locally from `timeRemaining`. |
| Create player list & result overlay | dart-developer | `frontend/lib/blackjack/roulette/widgets/player_list.dart`, `frontend/lib/blackjack/roulette/widgets/result_overlay.dart` | **player_list.dart**: Simple `ListView` of player names with their total bet amount for this round. Green dot prefix. Shows "(you)" next to current user. **result_overlay.dart**: `ResultOverlay` widget shown briefly (3s) when phase changes to 'result'. Shows winning number in a colored circle, then lists your payout ("+$150" in green or "-$10" in red). Animated opacity (fade in/out). Dismissible on tap. |

### Wave 6: Leaderboard Update
| Sub-task | Agent | Files | Details |
|----------|-------|-------|---------|
| Update leaderboard endpoint | developer | `functions/api/blackjack/leaderboard.js` | Add `roulette_results` to the daily query: LEFT JOIN `roulette_results` on user_id and date. Add `spins_played` field to the response for each player. The profit already comes from the shared balance in `blackjack_sessions`/`blackjack_results` so no profit calculation change needed. For monthly: also JOIN and SUM `spins_played`. Return `spins_played` in both daily and monthly response arrays. |
| Update lobby leaderboard display | dart-developer | `frontend/lib/blackjack/blackjack_lobby_screen.dart` | In `_buildLeaderboard()`, if the leaderboard row has `spins_played > 0`, show it as an additional stat (e.g., "5 hands, 3 spins" instead of just "5 hands"). Minor display tweak. |

### Wave 7: Review
| Sub-task | Agent | Details |
|----------|-------|---------|
| Review all changes | reviewer | Full review of all files created/modified. Check: WebSocket protocol matches spec exactly, payout math is correct (straight 35:1, even bets 1:1), wheel order matches European standard, balance sync pattern matches blackjack (fresh D1 read on each bet), alarm loop starts/stops correctly, edge cases handled (mid-spin join, disconnect with active bets, cashed-out spectator mode, concurrent blackjack+roulette balance access). Verify naming conventions, error handling, and no regressions to existing blackjack functionality. |

## Files Expected to Change

### New Files
| File | Description |
|------|-------------|
| `wrangler-roulette-worker.toml` | Cloudflare Worker config for roulette |
| `migrations/0020_roulette.sql` | D1 schema for roulette_results table |
| `src/roulette-worker.js` | RouletteTable Durable Object + default fetch handler |
| `functions/api/roulette/status.js` | Pages Function — GET table status for lobby |
| `frontend/lib/blackjack/roulette/models/roulette_state.dart` | Data models |
| `frontend/lib/blackjack/roulette/roulette_websocket.dart` | WebSocket client |
| `frontend/lib/blackjack/roulette/roulette_screen.dart` | Main game screen |
| `frontend/lib/blackjack/roulette/widgets/roulette_wheel.dart` | Animated wheel |
| `frontend/lib/blackjack/roulette/widgets/betting_table.dart` | Clickable betting grid |
| `frontend/lib/blackjack/roulette/widgets/bet_chips.dart` | Chip amount selector |
| `frontend/lib/blackjack/roulette/widgets/phase_timer.dart` | Phase countdown timer |
| `frontend/lib/blackjack/roulette/widgets/player_list.dart` | Connected players display |
| `frontend/lib/blackjack/roulette/widgets/result_overlay.dart` | Win/loss animation |

### Modified Files
| File | Change |
|------|--------|
| `frontend/lib/blackjack/blackjack_lobby_screen.dart` | Rename class to `CasinoLobbyScreen`, add Blackjack/Roulette toggle, add roulette status polling, add roulette navigation state |
| `frontend/lib/main.dart` | Update import and class reference from `BlackjackLobbyScreen` to `CasinoLobbyScreen` |
| `functions/api/blackjack/leaderboard.js` | Add LEFT JOIN on `roulette_results` for spins_played stat |
