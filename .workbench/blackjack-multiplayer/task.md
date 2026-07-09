# Task: Blackjack Multiplayer ("Play with Friends")

## User Request
Add multiplayer blackjack to the existing Stack.IT game. Up to 4 players sit at one table, bet from their shared daily balance, and play sequentially against a single dealer. Uses WebSockets via Cloudflare Durable Objects (same pattern as Chess PVP). Open lobby — anyone can see and join games.

## Codebase Summary
- **Stack**: Cloudflare Workers (Durable Objects) + Cloudflare Pages Functions + Flutter Web (Dart). Node.js for wrangler CLI. D1 (SQLite) for persistence.
- **Structure**:
  - `src/` — Worker entry points and shared backend logic (chess-game-worker.js, db.js, auth.js)
  - `functions/api/` — Cloudflare Pages Functions (REST endpoints per game)
  - `frontend/lib/` — Flutter app organized by feature (blackjack/, chess/, models/, services/, screens/)
  - `migrations/` — D1 SQL migrations (currently up to 0018)
  - `wrangler-*.toml` — Per-worker config files
- **Conventions**:
  - Workers: single-file DurableObject class + default export with fetch handler routing
  - Pages Functions: `onRequestGet` / `onRequestPost` exports, use `requireAuth`, `jsonResponse`, `errorResponse` from `src/db.js`
  - Flutter: StatefulWidget pattern, direct HTTP via `http` package, WebSocket via `web_socket_channel`, `AppTheme` passed through props
  - WebSocket client: class with `connect()`, `send()`, helper methods, auto-reconnect on close
  - Colors: `theme.correct` = green (player identity), `theme.present` = yellow/amber (active turn indicator)
  - Card format: `{ suit: 'hearts'|'diamonds'|'clubs'|'spades', rank: '2'-'A' }`
- **Critical Findings**:
  - Spec references `theme.incorrect` for turn indicator but `AppTheme` has no `incorrect` field — use `theme.present` (yellow/amber) instead as it serves the same purpose
  - Latest migration is `0018_blackjack.sql` → new migration should be `0019_blackjack_multiplayer.sql`
  - The chess-pvp join function uses `env.CHESS_GAME` service binding — the blackjack-mp version needs `env.BLACKJACK_GAME` binding configured in Cloudflare Pages settings after deploy

## Relevant Files
- `src/chess-game-worker.js` — Reference DO pattern (state get/save, WebSocket accept, broadcast, message switch, reconnect handling)
- `wrangler-chess-worker.toml` — Worker config pattern (bindings, migrations, d1)
- `frontend/lib/chess/pvp_websocket.dart` — WebSocket client pattern (connect, auto-reconnect, join on connect, dispose)
- `frontend/lib/chess/pvp_game_screen.dart` — Multiplayer game screen reference (init ws, handle messages, state management)
- `functions/api/chess-pvp/join/[sessionId].js` — WebSocket proxy (3 lines: get id from name, get stub, return stub.fetch)
- `frontend/lib/blackjack/blackjack_lobby_screen.dart` — Current lobby UI (status card, play button, leaderboard)
- `frontend/lib/blackjack/blackjack_screen.dart` — Card rendering, hand value calc, betting UI, action buttons
- `functions/api/blackjack/bet.js` — createDeck(), cardValue(), handValue(), isBlackjack(), drawCard() logic
- `functions/api/blackjack/today.js` — Session creation pattern (defaultSession, INSERT if not exists)
- `src/db.js` — getToday(), jsonResponse(), errorResponse(), requireAuth()
- `migrations/0018_blackjack.sql` — Schema pattern (blackjack_sessions, blackjack_results tables)

## Execution Plan

### Wave 1: Config & Schema (no dependencies)

| Sub-task | Agent | Details |
|----------|-------|---------|
| Create wrangler config | developer | Create `wrangler-blackjack-worker.toml` with: name=`fuseit-blackjack-worker`, main=`src/blackjack-mp-worker.js`, compatibility_date=`2024-01-01`, D1 binding (DB, fuseit-wordle-db, database_id=`b9d40390-9784-44c1-a05c-ded1ede17ba5`), DO binding (BLACKJACK_GAME, class=BlackjackMultiplayerSession), migration tag=v1 with new_sqlite_classes. Follow exact format of `wrangler-chess-worker.toml`. |
| Create D1 migration | developer | Create `migrations/0019_blackjack_multiplayer.sql` with: `blackjack_mp_games` table (id TEXT PK, creator_id INTEGER NOT NULL, creator_name TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'waiting', player_count INTEGER NOT NULL DEFAULT 1, max_players INTEGER NOT NULL DEFAULT 4, created_at TEXT NOT NULL, finished_at TEXT) + index on status. |

### Wave 2: Backend — Durable Object Worker + Pages Functions

| Sub-task | Agent | Details |
|----------|-------|---------|
| Implement Durable Object worker | developer | Create `src/blackjack-mp-worker.js`. Must implement `BlackjackMultiplayerSession` DO class (extends DurableObject) and default fetch export with `/join/:gameId` routing. The DO must handle: **State machine** (WAITING→BETTING→DEALING→PLAYING→DEALER_TURN→ROUND_OVER→WAITING loop). **WebSocket handling**: accept pair, tag with userId/name via serializeAttachment, handle join/reconnect (re-attach existing player, send game_state snapshot). **Game logic**: reuse createDeck/cardValue/handValue/isBlackjack/drawCard from bet.js; implement sequential turns (hit/stand/double); dealer plays (hit until ≥17); resolve outcomes (blackjack 3:2, win 2:1, push, lose). **Balance sync**: on bet placement read balance from D1 `blackjack_sessions`, verify sufficient funds, deduct immediately (write back); on round resolve write final balances + increment handsPlayed/handsWon/blackjacks. Check `blackjack_results` for cashout before allowing bet. **Timeouts**: 30s betting phase timer, 30s per-turn inactivity timer (auto-stand). **Lobby sync**: update `blackjack_mp_games` in D1 (player_count on join/leave, status on start/finish). **Cleanup**: mark game finished + close sockets when all players leave; transfer creator on creator leave. **Broadcast**: all server→client messages per spec protocol (game_state, player_joined, player_left, betting_phase, bet_placed, cards_dealt, turn_start, card_drawn, player_stood, player_doubled, player_bust, dealer_turn, round_result, error, player_disconnected, player_reconnected). |
| Create POST /api/blackjack-mp/create | developer | Create `functions/api/blackjack-mp/create.js`. Export `onRequestPost`. requireAuth → get userId + query users table for nickname. Ensure player has blackjack_sessions row for today (create with defaultSession if missing, same as today.js). Generate UUID (crypto.randomUUID()). INSERT into blackjack_mp_games (id, creator_id, creator_name, status='waiting', player_count=1, max_players=4, created_at=new Date().toISOString()). Return jsonResponse({ gameId, status: 'waiting' }). |
| Create GET /api/blackjack-mp/games | developer | Create `functions/api/blackjack-mp/games.js`. Export `onRequestGet`. requireAuth. SELECT id, creator_name, status, player_count, max_players, created_at FROM blackjack_mp_games WHERE status != 'finished' ORDER BY created_at DESC. Return jsonResponse({ games: [...] }). |
| Create GET /api/blackjack-mp/join/[gameId] | developer | Create `functions/api/blackjack-mp/join/[gameId].js`. Export `onRequestGet`. Extract gameId from params. Get DO stub via `env.BLACKJACK_GAME.idFromName(gameId)` → `env.BLACKJACK_GAME.get(id)` → return `stub.fetch(request)`. Identical pattern to `functions/api/chess-pvp/join/[sessionId].js`. |

### Wave 3: Frontend — WebSocket Client

| Sub-task | Agent | Details |
|----------|-------|---------|
| Create BlackjackMpWebSocket | dart-developer | Create `frontend/lib/blackjack/blackjack_mp_websocket.dart`. Mirror `pvp_websocket.dart` pattern exactly. Class with: `_channel`, `onMessage` callback, private `_gameId`/`_userId`/`_name`/`_intentionallyClosed` fields. `connect(gameId, userId, name)` — construct ws/wss URI to `/api/blackjack-mp/join/$gameId`, connect, listen to stream, call onMessage with decoded JSON, auto-reconnect on close (2s delay) unless intentionally closed, emit `{'type': 'connection_lost'}` on done. Auto-send `{'type': 'join', 'userId': userId, 'name': name, 'gameId': gameId}` on connect. Helper methods: `startRound()`, `placeBet(int amount)`, `hit()`, `stand()`, `doubleBet()`, `leave()`. `dispose()` sets intentionallyClosed=true and closes sink. |

### Wave 4: Frontend — Screens

| Sub-task | Agent | Details |
|----------|-------|---------|
| Modify blackjack_lobby_screen.dart | dart-developer | Add multiplayer section to existing lobby. **Changes**: (1) Add state: `List<Map<String, dynamic>> _mpGames = []`, `bool _mpLoading = false`. (2) In `_load()`, also fetch `GET /api/blackjack-mp/games` and populate `_mpGames`. (3) Add a "Play with Friends" button below the existing Play Solo button — calls `POST /api/blackjack-mp/create`, on success navigates to `BlackjackMpScreen` with returned gameId. Style: same width/height as play solo button, use `theme.present` background color, icon `Icons.people`. (4) Add "Open Tables" section between the buttons and leaderboard — show list of games from `_mpGames` (creator name, player_count/max_players, status). Each row has a "Join" button that navigates to `BlackjackMpScreen` with that game's id. Hide join button if status='playing' and player_count=max_players. (5) Add auto-refresh: Timer.periodic(5s) to re-fetch games list while on lobby screen (dispose timer). (6) Import `BlackjackMpScreen`. |
| Create blackjack_mp_screen.dart | dart-developer | Create `frontend/lib/blackjack/blackjack_mp_screen.dart`. Full multiplayer game UI connected via WebSocket. **Constructor params**: theme, onBack, nickname, userId, gameId. **State**: BlackjackMpWebSocket instance, phase (waiting/betting/playing/dealer_turn/round_over), players list (userId, name, seatIndex, balance, bet, hand, value, status), dealer (hand, value), currentTurn index, creatorId, myBalance, error string. **Init**: create ws, connect, set onMessage handler. **Message handling**: big switch on type — update state from all server→client messages per protocol. `game_state` does full state replacement. Individual messages do incremental updates. **UI Layout**: (a) Header bar with "Table: [gameId.substring(0,8)]" + "Leave Table" button (calls ws.leave() then onBack). (b) Dealer area (top center) — show cards using same card-rendering pattern from blackjack_screen.dart (_buildCard widget), show value (hidden if hole card not revealed). (c) Player seats (horizontal row/wrap) — 1-4 containers showing: name, bet amount, cards, hand value, status text (waiting/playing/stood/bust). Current user's seat gets `theme.correct` (green) border. Active turn player's seat gets `theme.present` (yellow) border (overrides green if it's the user's turn). (d) Action area: During WAITING phase show "Waiting for players..." or "Start Round" button (if user is creator and ≥2 players). During BETTING phase show bet input (same chip selector UI from blackjack_screen: 5/10/25/50/All-In chips + slider + confirm button). During PLAYING phase (user's turn) show Hit/Stand/Double buttons; Double only enabled on first action. During others' turn, show "Waiting for [name]..." text. (e) Round results overlay: after round_result, show results per player (outcome, payout) for 5 seconds then auto-dismiss. (f) Balance display at bottom. **Reconnection**: on `connection_lost` show reconnecting indicator, on `game_state` re-render from scratch. **Dispose**: ws.dispose(). |

### Wave 5: Review

| Sub-task | Agent | Details |
|----------|-------|---------|
| Review all changes | reviewer | Full review of all created/modified files against spec and project conventions. Check: WebSocket protocol messages match between DO and Flutter client. Balance sync logic is correct (deduct on bet, resolve on round end). State machine transitions are complete. Card rendering matches solo game. Theme colors used correctly (correct=green for identity, present=yellow for turn). Error handling present. No hardcoded secrets. Pages function auth pattern followed. DO cleanup logic covers all edge cases (disconnect, leave, creator transfer). |

## Files Expected to Change

**New files:**
- `wrangler-blackjack-worker.toml`
- `migrations/0019_blackjack_multiplayer.sql`
- `src/blackjack-mp-worker.js`
- `functions/api/blackjack-mp/create.js`
- `functions/api/blackjack-mp/games.js`
- `functions/api/blackjack-mp/join/[gameId].js`
- `frontend/lib/blackjack/blackjack_mp_websocket.dart`
- `frontend/lib/blackjack/blackjack_mp_screen.dart`

**Modified files:**
- `frontend/lib/blackjack/blackjack_lobby_screen.dart`
