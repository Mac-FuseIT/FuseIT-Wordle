# Blackjack Multiplayer ("Play with Friends") — Design

## Overview

Add multiplayer blackjack to the existing Stack.IT game. Up to 4 players sit at one table, bet from their shared daily balance, and play sequentially against a single dealer. Uses WebSockets via Cloudflare Durable Objects (same pattern as Chess PVP). Open lobby — anyone can see and join games.

## Goals & Non-Goals

**Goals:**
- Real-time multiplayer blackjack for 2–4 players via WebSockets
- Shared deck, sequential turns, individual bet resolution
- Balance shared between solo and multiplayer (same `blackjack_sessions` row)
- Open lobby visible to all ~38 users
- Smooth reconnection handling

**Non-Goals:**
- Split, insurance, or surrender actions (keep it simple like solo)
- Private/invite-only rooms
- Spectator mode (only players at the table)
- Chat system
- Multi-deck shoe (single 52-card deck, reshuffled when low)

---

## Architecture Overview

### New Cloudflare Worker + Durable Object

File: `src/blackjack-mp-worker.js`
Config: `wrangler-blackjack-worker.toml`

```toml
name = "fuseit-blackjack-worker"
main = "src/blackjack-mp-worker.js"
compatibility_date = "2024-01-01"

[[d1_databases]]
binding = "DB"
database_name = "fuseit-wordle-db"
database_id = "b9d40390-9784-44c1-a05c-ded1ede17ba5"

[[durable_objects.bindings]]
name = "BLACKJACK_GAME"
class_name = "BlackjackMultiplayerSession"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["BlackjackMultiplayerSession"]
```

### Request Flow

```
Flutter Client
    │
    ├─ HTTP ──► /api/blackjack-mp/create   (Pages Function → D1)
    ├─ HTTP ──► /api/blackjack-mp/games    (Pages Function → D1)
    │
    └─ WS  ──► /api/blackjack-mp/join/{gameId}
                    │
                    ▼
               Pages Function (proxy)
                    │
                    ▼
               fuseit-blackjack-worker
                    │
                    ▼
               BlackjackMultiplayerSession (Durable Object)
                    │
                    ├─ ctx.storage (game state, deck, hands)
                    └─ env.DB (balance sync read/write)
```

### DB Schema Changes

New migration: `migrations/0019_blackjack_multiplayer.sql`

```sql
CREATE TABLE IF NOT EXISTS blackjack_mp_games (
  id TEXT PRIMARY KEY,
  creator_id INTEGER NOT NULL,
  creator_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'waiting',  -- waiting | playing | finished
  player_count INTEGER NOT NULL DEFAULT 1,
  max_players INTEGER NOT NULL DEFAULT 4,
  created_at TEXT NOT NULL,
  finished_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_bj_mp_status ON blackjack_mp_games(status);
```

The Durable Object stores all in-round state (deck, hands, bets, turn order) in `ctx.storage`. The D1 table is only for lobby listing and balance sync.

---

## WebSocket Protocol

All messages are JSON. The `type` field determines the message kind.

### Client → Server Messages

| Type | Payload | When |
|------|---------|------|
| `join` | `{ userId, name, gameId }` | On connect (auto-sent) |
| `start_round` | `{}` | Creator starts the round (min 2 players) |
| `place_bet` | `{ amount: number }` | During betting phase |
| `hit` | `{}` | During player's turn |
| `stand` | `{}` | During player's turn |
| `double` | `{}` | During player's turn (first action only) |
| `leave` | `{}` | Player leaves the table |

### Server → Client Messages

| Type | Payload | Description |
|------|---------|-------------|
| `game_state` | Full state snapshot | Sent on join/reconnect |
| `player_joined` | `{ userId, name, seatIndex }` | New player sat down |
| `player_left` | `{ userId, name }` | Player departed |
| `round_starting` | `{ players: [...] }` | Round initiated by creator |
| `betting_phase` | `{ timeout: 30 }` | All players must bet |
| `bet_placed` | `{ userId, name, amount }` | A player locked in their bet |
| `cards_dealt` | `{ players: [{userId, hand, value}], dealer: {hand, value} }` | Initial deal (dealer 2nd card hidden) |
| `turn_start` | `{ userId, name, canDouble: bool }` | Whose turn it is |
| `card_drawn` | `{ userId, card, hand, value }` | Player hit result |
| `player_stood` | `{ userId, hand, value }` | Player stood |
| `player_doubled` | `{ userId, card, hand, value, newBet }` | Player doubled |
| `player_bust` | `{ userId, hand, value }` | Player busted |
| `dealer_turn` | `{ cards: [...], finalHand, finalValue }` | Dealer reveals + draws |
| `round_result` | `{ results: [{userId, outcome, payout, newBalance}], dealerHand, dealerValue }` | Round complete |
| `balance_updated` | `{ userId, balance }` | Balance sync confirmation |
| `error` | `{ message }` | Validation error |
| `player_disconnected` | `{ userId, name }` | WebSocket dropped |
| `player_reconnected` | `{ userId, name }` | Player came back |

### State Snapshot (`game_state`)

Sent to a player on join/reconnect. Contains everything needed to render the current state:

```json
{
  "type": "game_state",
  "gameId": "uuid",
  "phase": "waiting|betting|playing|dealer_turn|round_over",
  "players": [
    { "userId": 1, "name": "Alice", "seatIndex": 0, "balance": 320, "bet": 50, "hand": [...], "value": 17, "status": "playing|stood|bust|done" }
  ],
  "dealer": { "hand": [...], "value": 10 },
  "currentTurn": 0,
  "creatorId": 1,
  "deckRemaining": 38
}
```

---

## API Endpoints

### HTTP Endpoints (Pages Functions)

#### `POST /api/blackjack-mp/create`

Creates a new multiplayer game. Inserts row into `blackjack_mp_games`.

**Request:** `{ }` (auth via Bearer token)

**Response:**
```json
{ "gameId": "uuid", "status": "waiting" }
```

**Logic:**
1. Verify auth, get userId + nickname
2. Check player has an active `blackjack_sessions` row today (create if not, like solo does)
3. Check player isn't already in another active game (query `blackjack_mp_games` with status != 'finished' and creator_id = userId — or check DO state)
4. Insert into `blackjack_mp_games`
5. Return gameId

**File:** `functions/api/blackjack-mp/create.js`

---

#### `GET /api/blackjack-mp/games`

Lists all open/active multiplayer games for the lobby.

**Response:**
```json
{
  "games": [
    { "id": "uuid", "creatorName": "Alice", "status": "waiting", "playerCount": 2, "maxPlayers": 4, "createdAt": "..." },
    { "id": "uuid", "creatorName": "Bob", "status": "playing", "playerCount": 3, "maxPlayers": 4, "createdAt": "..." }
  ]
}
```

**Logic:** `SELECT * FROM blackjack_mp_games WHERE status != 'finished' ORDER BY created_at DESC`

**File:** `functions/api/blackjack-mp/games.js`

---

#### `GET /api/blackjack-mp/join/{gameId}` (WebSocket Upgrade)

Proxies WebSocket upgrade to the Durable Object worker.

**File:** `functions/api/blackjack-mp/join/[gameId].js`

```js
export async function onRequestGet({ params, request, env }) {
  const gameId = params.gameId;
  const id = env.BLACKJACK_GAME.idFromName(gameId);
  const stub = env.BLACKJACK_GAME.get(id);
  return stub.fetch(request);
}
```

Requires `BLACKJACK_GAME` binding in Pages project settings (service binding to `fuseit-blackjack-worker`).

---

## Game State Machine

```
┌─────────────┐
│   WAITING   │  Players join/leave. Creator sees "Start Round" button.
│  (lobby)    │  Min 2 players required.
└──────┬──────┘
       │ creator sends `start_round`
       ▼
┌─────────────┐
│   BETTING   │  All players have 30s to place bets.
│             │  Players who don't bet in time are skipped for this round.
└──────┬──────┘
       │ all bets placed (or timeout)
       ▼
┌─────────────┐
│   DEALING   │  Cards dealt: 2 per player, 2 for dealer (1 face-down).
│             │  Check for player/dealer blackjacks.
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   PLAYING   │  Sequential turns. Current player can hit/stand/double.
│             │  On bust or stand → next player.
│             │  After all players done → dealer turn.
└──────┬──────┘
       │ all players resolved
       ▼
┌─────────────────┐
│  DEALER_TURN    │  Dealer reveals hole card, hits until ≥17.
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  ROUND_OVER     │  Results calculated, balances updated, synced to D1.
│                 │  After 5s → back to WAITING for next round.
└──────┬──────────┘
       │ auto-transition
       ▼
┌─────────────┐
│   WAITING   │  (loop — players can leave or play again)
└─────────────┘
```

### State Transitions

| From | Event | To | Condition |
|------|-------|----|-----------|
| WAITING | `start_round` | BETTING | sender is creator, ≥2 players |
| BETTING | all bets in / timeout | DEALING | — |
| DEALING | cards dealt | PLAYING | no immediate blackjacks resolve all |
| DEALING | blackjack(s) | ROUND_OVER | if all hands resolved by BJ |
| PLAYING | player busts/stands | PLAYING (next) | more players remain |
| PLAYING | last player done | DEALER_TURN | — |
| DEALER_TURN | dealer done | ROUND_OVER | — |
| ROUND_OVER | 5s timer | WAITING | — |
| ANY | all players leave | FINISHED | game deleted from lobby |

---

## Frontend Screens & Widgets

### Modified: `blackjack_lobby_screen.dart`

Add a "Play with Friends" section between the Play button and the leaderboard:

```
┌────────────────────────────────────┐
│  Stack.IT — Lobby                  │
├────────────────────────────────────┤
│  [Status Card: balance, profit]    │
│                                    │
│  [▶ Play Solo]                     │
│  [👥 Play with Friends]  ← NEW    │
│                                    │
│  ── Open Tables ──         ← NEW  │
│  | Alice's table | 2/4 | [Join] | │
│  | Bob's table   | 3/4 | [Join] | │
│                                    │
│  ── Leaderboard ──                 │
│  [Daily] [Monthly]                 │
│  ...                               │
└────────────────────────────────────┘
```

**Changes:**
- Add "Play with Friends" button → calls `POST /api/blackjack-mp/create`, then navigates to multiplayer screen
- Add "Open Tables" list → polls `GET /api/blackjack-mp/games` every 5s (or on pull-to-refresh)
- Each table row shows: creator name, player count, "Join" button
- Tapping Join navigates to multiplayer game screen with that gameId

### New: `blackjack_mp_screen.dart`

The multiplayer game screen. Connected via WebSocket.

**Layout (desktop/wide):**
```
┌─────────────────────────────────────────────────────┐
│  Table: [gameId short]          [Leave Table]       │
├─────────────────────────────────────────────────────┤
│                                                     │
│              ┌─────────────────┐                    │
│              │  DEALER          │                    │
│              │  [?][7♠]         │                    │
│              │  Value: ?        │                    │
│              └─────────────────┘                    │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│  │ Player 1 │  │ Player 2 │  │ Player 3 │         │
│  │ "Alice"  │  │ "Bob" ◀  │  │ "You" 🟢 │         │  ← green=you, yellow=active turn
│  │ Bet: $50 │  │ Bet: $25 │  │ Bet: $30 │         │
│  │ [K♥][8♦] │  │ [5♣][J♠] │  │ [A♠][9♥] │         │
│  │ Val: 18  │  │ Val: 15  │  │ Val: 20  │         │
│  │ ✓ stood  │  │ ← TURN   │  │ waiting  │         │
│  └──────────┘  └──────────┘  └──────────┘         │
│                                                     │
│  ── Your Actions ──                                 │
│  [HIT]  [STAND]  [DOUBLE]     Balance: $270        │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Key UI elements:**
- Dealer area (top center) — shows cards, value
- Player seats (arranged horizontally) — 1-4 slots
- Current user's seat has a `theme.correct` (green) border + "You" label to distinguish from other players
- Whoever's turn it is gets a `theme.incorrect` (yellow/orange) border — applies to ANY player including yourself
- If it's your turn, `theme.incorrect` takes priority over `theme.correct` (turn indicator beats identity marker)
- Turn indicator: active player's seat border changes to `theme.incorrect` colour (no arrow needed — the colour IS the indicator)
- Action buttons only enabled when it's the current user's turn
- Bet input (shown during BETTING phase)
- "Start Round" button visible only to creator during WAITING phase
- "Waiting for players..." message during WAITING phase
- Results overlay after ROUND_OVER (win/loss per player, payout)

### New: `blackjack_mp_websocket.dart`

WebSocket client (mirrors `pvp_websocket.dart` pattern):

```dart
class BlackjackMpWebSocket {
  WebSocketChannel? _channel;
  void Function(Map<String, dynamic>)? onMessage;

  void connect(String gameId, int userId, String name) { ... }
  void send(Map<String, dynamic> data) { ... }
  void startRound() => send({'type': 'start_round'});
  void placeBet(int amount) => send({'type': 'place_bet', 'amount': amount});
  void hit() => send({'type': 'hit'});
  void stand() => send({'type': 'stand'});
  void double_() => send({'type': 'double'});
  void leave() => send({'type': 'leave'});
  void dispose() { ... }
}
```

Auto-reconnect on disconnect (2s delay, re-sends `join` on reconnect to get `game_state` snapshot).

---

## Balance Sync Mechanism

The core challenge: solo and multiplayer share the same balance in `blackjack_sessions`.

### Read Balance (on join / round start)

When a player joins a game or a new round starts, the DO reads their current balance from D1:

```js
const row = await env.DB.prepare(
  'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
).bind(userId, today).first();
const session = JSON.parse(row.session_state);
const balance = session.balance;
```

If no session exists, create one with default $100 (same as `today.js` does).

### Write Balance (after round resolves)

After each round, the DO writes updated balances back to D1 for each player:

```js
// For each player in the round:
const row = await env.DB.prepare(
  'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
).bind(player.userId, today).first();
const session = JSON.parse(row.session_state);
session.balance = player.newBalance;
session.handsPlayed += 1;
if (player.outcome === 'win' || player.outcome === 'blackjack') session.handsWon += 1;
if (player.outcome === 'blackjack') session.blackjacks += 1;
await env.DB.prepare(
  'UPDATE blackjack_sessions SET session_state = ? WHERE user_id = ? AND date = ?'
).bind(JSON.stringify(session), player.userId, today).run();
```

### Concurrency Protection

Since only ~38 users exist and a player can only be in one game at a time, race conditions are minimal. However, to prevent a player from betting in solo AND multiplayer simultaneously:

1. **On bet placement in DO:** Read latest balance from D1 at bet time, verify sufficient funds, then deduct immediately:
   - Read `session_state` → check `balance >= betAmount`
   - Write `balance -= betAmount` back to D1 immediately
   - If the write succeeds, the bet is locked in

2. **On round result:** Write final balance (original balance - bet + payout) back to D1.

3. **Solo play check:** The solo `bet.js` endpoint already checks `session.balance`. Since the DO deducts balance on bet placement, a concurrent solo bet will see the reduced balance and reject if insufficient.

### Cashed Out Check

If a player has already cashed out today (`blackjack_results` row exists), they cannot place bets in multiplayer. The DO checks this on `place_bet`.

---

## Edge Cases

### Player Disconnects Mid-Round

- **During BETTING phase:** If a player disconnects before placing a bet, they are skipped for that round (no bet, no cards). They remain at the table and can rejoin.
- **During PLAYING phase (their turn):** 30-second timeout. If they don't act, auto-stand. Their hand plays out with whatever they have.
- **During PLAYING phase (not their turn):** No impact on game flow. They'll get `game_state` snapshot on reconnect.
- **During DEALER_TURN / ROUND_OVER:** No impact. Results are calculated server-side.

### Player Reconnects

On WebSocket reconnect, player sends `join` again. DO recognizes existing player (by userId), re-attaches the WebSocket, and sends full `game_state` snapshot. No duplicate seat created.

### Player Leaves Mid-Round

- If a player sends `leave` or disconnects permanently during an active round:
  - Their current hand auto-stands (or is marked as abandoned)
  - Their bet remains in play and resolves normally against the dealer
  - The result (win/loss) applies to their balance regardless
  - They are removed from the player list for subsequent rounds
- If the last player leaves, game status → `finished`

### Insufficient Balance

- On `place_bet`: DO reads current balance from D1. If `balance < amount`, send `error` message. Player can try a lower bet.
- If player's balance is $0, they cannot bet and are skipped for the round (but can watch).

### Deck Exhaustion

- Standard 52-card deck. With 4 players + dealer, max cards per round ≈ 25 (worst case).
- If deck drops below 10 cards at the start of a round, reshuffle a fresh 52-card deck.
- Mid-round: if deck runs out, reshuffle excluding all cards currently in play (same logic as solo).

### Creator Leaves

- If the game creator leaves during WAITING phase, the next player in seat order becomes the new creator (can start rounds).
- If creator leaves mid-round, round continues normally. New creator assigned for next round.

### Already Cashed Out

- If a player has cashed out today, they can still join and watch but cannot place bets. The DO checks `blackjack_results` table on bet placement.

### Simultaneous Solo Play

- A player can't be mid-hand in solo AND multiplayer simultaneously because:
  - Multiplayer deducts balance from D1 on bet placement
  - Solo's `bet.js` reads the same D1 row and will see reduced balance
  - No explicit lock needed for 38 users with single-row-per-user-per-day design

### Betting Timeout

- 30-second timer for betting phase. Players who haven't bet when timer expires are skipped (sit out that round). They stay at the table for the next round.

### Game Cleanup

- Games in `waiting` status with no connected players for 5 minutes → auto-cleanup (DO alarm or periodic check)
- Games marked `finished` are excluded from lobby query

---

## Design Decisions

### 1. Separate Worker (not merged with Chess)

**Decision:** New `fuseit-blackjack-worker` with its own `BlackjackMultiplayerSession` DO class.

**Rationale:** Keeps concerns separate, allows independent deployment, avoids bloating the chess worker. Both workers share the same D1 database. Matches the project's existing pattern of one-worker-per-game.

### 2. Balance Deduction at Bet Time (not Round End)

**Decision:** Deduct from D1 immediately when bet is placed, not when round resolves.

**Rationale:** Prevents double-spending between solo and multiplayer. If we only deducted at round end, a player could bet $50 in multiplayer and $50 in solo simultaneously with only $80 balance. Immediate deduction makes the balance authoritative.

### 3. Open Lobby (not Invite-Based)

**Decision:** All games visible to all users. No invite codes or friend lists.

**Rationale:** With only ~38 users in the office, discoverability is more important than privacy. Simpler UX — one tap to join.

### 4. Sequential Play (not Simultaneous)

**Decision:** Players act one at a time in fixed order.

**Rationale:** More social/fun to watch others play. Simpler state management. Avoids race conditions on shared deck. Standard casino blackjack rules.

### 5. D1 for Lobby Listing, DO Storage for Game State

**Decision:** The `blackjack_mp_games` table tracks game existence/status for lobby queries. All in-game state (deck, hands, bets, turns) lives in the DO's `ctx.storage`.

**Rationale:** Pages Functions can't query DO state directly for lobby listing. D1 provides a queryable registry. DO storage is fast, transactional, and co-located with the WebSocket logic.

### 6. No Persistent Game History Table

**Decision:** Don't create a `blackjack_mp_results` table. Wins/losses are reflected in the existing `blackjack_sessions` state (handsPlayed, handsWon, balance) which feeds into `blackjack_results` on cashout.

**Rationale:** The user's daily stats already capture multiplayer outcomes through balance sync. Adding a separate table would duplicate data. The leaderboard already works off `blackjack_results`.

---

## Tasks

1. **Create `wrangler-blackjack-worker.toml` config** — S
2. **Create migration `0019_blackjack_multiplayer.sql`** — S
3. **Implement `BlackjackMultiplayerSession` Durable Object** (`src/blackjack-mp-worker.js`) — L
   - State management (phases, deck, hands, turns)
   - WebSocket handling (join, reconnect, broadcast)
   - Game logic (deal, hit, stand, double, dealer play, resolve)
   - Balance sync (read/write D1 on bet/resolve)
   - Timeout handling (betting timer, turn timer)
   - Cleanup (game over, all players leave)
4. **Create `POST /api/blackjack-mp/create`** Pages Function — S
5. **Create `GET /api/blackjack-mp/games`** Pages Function — S
6. **Create `GET /api/blackjack-mp/join/[gameId]`** WebSocket proxy Pages Function — S
7. **Create `blackjack_mp_websocket.dart`** Flutter WebSocket client — M
8. **Modify `blackjack_lobby_screen.dart`** — add "Play with Friends" button + open tables list — M
9. **Create `blackjack_mp_screen.dart`** — multiplayer game UI — L
   - Player seat widgets (hand, bet, status, name)
   - Dealer area
   - Action buttons (context-sensitive)
   - Betting input
   - Round results overlay
   - Reconnection handling
10. **Deploy worker + bind to Pages project** — S
11. **Run migration on D1** — S
12. **End-to-end testing** (2+ browser tabs) — M

## Open Questions

None — all requirements confirmed.
