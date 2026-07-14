# Roulette (Spin.IT) — Design Spec

## Overview

A European Roulette game for Fuse Arcade. Single persistent table that all players share — anyone can join, place bets during the betting window, and watch the wheel spin together. Shares the daily $100 casino balance with blackjack. Lives inside the existing blackjack lobby (renamed to "Casino" lobby).

## Goals & Non-Goals

**Goals:**
- European Roulette (single zero, 37 pockets) with simple bet types
- Persistent always-open multiplayer room (one global table)
- Continuous game loop: BETTING → SPINNING → RESULT → repeat
- Real-time bet visibility (see what friends are betting)
- Animated wheel spin with ball landing
- Shared $100 daily balance with blackjack
- Combined "Casino" leaderboard (blackjack + roulette profit)
- Seamless integration into existing lobby UI

**Non-Goals:**
- Complex bet types (splits, streets, corners, columns, dozens)
- Multiple roulette tables
- American roulette (double zero)
- Separate balance/currency system
- Chat functionality (can be added later)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter Web Frontend                                        │
│  ┌───────────────────┐  ┌─────────────────────────────────┐ │
│  │ Casino Lobby       │  │ Roulette Screen                 │ │
│  │ (was BJ Lobby)     │  │ - Wheel widget (animated)       │ │
│  │ - Status card      │→ │ - Betting table (clickable)     │ │
│  │ - BJ solo btn      │  │ - Player list + bets            │ │
│  │ - BJ friends btn   │  │ - Timer / phase indicator       │ │
│  │ - Roulette btn     │  │ - Results overlay               │ │
│  │ - Leaderboard      │  └─────────────────────────────────┘ │
│  └───────────────────┘                                       │
└──────────────────────────────┬──────────────────────────────┘
                               │ WebSocket
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  Cloudflare Worker: fuseit-roulette-worker                   │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Durable Object: RouletteTable                           │ │
│  │ - Single instance keyed "roulette-main"                 │ │
│  │ - Runs continuous BETTING→SPINNING→RESULT loop          │ │
│  │ - Manages WebSocket connections                         │ │
│  │ - Reads/writes D1 for balance                           │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────┬──────────────────────────────┘
                               │ D1 binding
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  D1 Database (fuseit-wordle-db)                              │
│  - blackjack_sessions (shared balance — reads/writes)        │
│  - blackjack_results (cashout records)                       │
│  - roulette_results (new — daily stats for leaderboard)      │
└─────────────────────────────────────────────────────────────┘
```

### Worker Configuration (`wrangler-roulette-worker.toml`)

```toml
name = "fuseit-roulette-worker"
main = "src/roulette-worker.js"
compatibility_date = "2024-01-01"

[[d1_databases]]
binding = "DB"
database_name = "fuseit-wordle-db"
database_id = "b9d40390-9784-44c1-a05c-ded1ede17ba5"

[[durable_objects.bindings]]
name = "ROULETTE_TABLE"
class_name = "RouletteTable"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["RouletteTable"]
```

### Integration with Existing Infra

- Same D1 database as blackjack/chess
- Same `blackjack_sessions` table for balance (no new balance table)
- New `roulette_results` table for daily stats (parallel to `blackjack_results`)
- Leaderboard endpoint updated to combine both games
- Lobby screen renamed and expanded (not a new screen)


---

## Game State Machine

The Durable Object runs a continuous loop. The loop runs **regardless of whether players are connected** — it just keeps cycling. When no players are connected, no bets are placed and no D1 writes happen (effectively idle but the alarm keeps ticking).

```
┌──────────┐   20s timer    ┌──────────┐   5s timer    ┌──────────┐   5s timer
│ BETTING  │ ─────────────→ │ SPINNING │ ─────────────→ │  RESULT  │ ─────────→ (loop)
│          │                │          │                │          │
│ Accept   │                │ Generate │                │ Calc     │
│ bets     │                │ winning  │                │ payouts  │
│ from     │                │ number   │                │ Update   │
│ players  │                │ Animate  │                │ balances │
└──────────┘                └──────────┘                └──────────┘
     ↑                                                        │
     └────────────────────────────────────────────────────────┘
```

### Phase Details

| Phase | Duration | Server Actions | Client Actions |
|-------|----------|---------------|----------------|
| BETTING | 20s | Accept bet messages, broadcast bets to all, validate balances | Show timer, enable bet placement, show others' bets |
| SPINNING | 5s | Generate winning number (RNG), broadcast spin result, reject late bets | Play wheel animation, disable betting |
| RESULT | 5s | Calculate payouts, write to D1, broadcast results | Show winning number, highlight winners, update balance |

### Loop Implementation

Uses Cloudflare Durable Object **alarms** (not `setTimeout`) for reliable timing:

```javascript
// In the DO:
async alarm() {
  const state = await this.getState();
  switch (state.phase) {
    case 'betting':
      await this.transitionToSpinning(state);
      break;
    case 'spinning':
      await this.transitionToResult(state);
      break;
    case 'result':
      await this.transitionToBetting(state);
      break;
  }
}
```

The loop starts when the first player connects and stops when the last player disconnects (to avoid pointless alarm cycling). When a player connects to an idle table, the DO immediately enters BETTING phase and sets the alarm.


---

## WebSocket Protocol

### Connection

Client connects to: `wss://{host}/api/roulette/join`

Single fixed room — no game ID needed. The worker routes all connections to the same DO instance keyed `"roulette-main"`.

### Client → Server Messages

#### `join`
Sent immediately after WebSocket connects.
```json
{
  "type": "join",
  "userId": 42,
  "name": "Mekhail"
}
```

#### `place_bet`
Place a bet during BETTING phase. Can send multiple times to place multiple bets.
```json
{
  "type": "place_bet",
  "betType": "straight",
  "betValue": 17,
  "amount": 5
}
```

`betType` values:
- `"straight"` — betValue: 0-36 (the number)
- `"red"` — betValue: null
- `"black"` — betValue: null
- `"odd"` — betValue: null
- `"even"` — betValue: null
- `"high"` — betValue: null (19-36)
- `"low"` — betValue: null (1-18)

#### `clear_bets`
Remove all bets for current round (only during BETTING phase).
```json
{
  "type": "clear_bets"
}
```

#### `leave`
Player intentionally leaves the table.
```json
{
  "type": "leave"
}
```

### Server → Client Messages

#### `game_state` (sent on join)
Full state snapshot so late joiners can sync.
```json
{
  "type": "game_state",
  "phase": "betting",
  "timeRemaining": 14500,
  "players": [
    { "userId": 42, "name": "Mekhail", "bets": [...] },
    { "userId": 7, "name": "Sarah", "bets": [...] }
  ],
  "yourBalance": 85,
  "yourBets": [...],
  "lastResult": { "winningNumber": 22, "color": "black" },
  "history": [22, 0, 15, 31, 8]
}
```

#### `player_joined`
```json
{
  "type": "player_joined",
  "userId": 7,
  "name": "Sarah"
}
```

#### `player_left`
```json
{
  "type": "player_left",
  "userId": 7,
  "name": "Sarah"
}
```

#### `bet_placed`
Broadcast when any player places a bet (so others see it live).
```json
{
  "type": "bet_placed",
  "userId": 42,
  "name": "Mekhail",
  "betType": "red",
  "betValue": null,
  "amount": 10
}
```

#### `bets_cleared`
```json
{
  "type": "bets_cleared",
  "userId": 42
}
```

#### `phase_change` — SPINNING
Sent when betting window closes. Includes the winning number so the client can animate the wheel landing on it.
```json
{
  "type": "spinning",
  "winningNumber": 17,
  "winningColor": "black",
  "totalBets": { "42": 25, "7": 10 }
}
```

#### `phase_change` — RESULT
Sent after spin animation completes (5s). Contains payouts.
```json
{
  "type": "result",
  "winningNumber": 17,
  "winningColor": "black",
  "payouts": [
    { "userId": 42, "name": "Mekhail", "totalWon": 175, "netProfit": 150, "newBalance": 235 },
    { "userId": 7, "name": "Sarah", "totalWon": 0, "netProfit": -10, "newBalance": 90 }
  ],
  "yourNewBalance": 235
}
```

#### `phase_change` — BETTING (new round)
```json
{
  "type": "betting",
  "timeRemaining": 20000,
  "roundNumber": 42
}
```

#### `error`
```json
{
  "type": "error",
  "message": "Insufficient balance"
}
```


---

## HTTP API Endpoints

Only one HTTP endpoint needed (for lobby info). The game itself is entirely WebSocket.

### `GET /api/roulette/status`

Returns current table status for the lobby card (who's playing, current phase). This is a Pages Function that queries the DO via fetch (non-WebSocket).

**Response:**
```json
{
  "players": [
    { "userId": 42, "name": "Mekhail" },
    { "userId": 7, "name": "Sarah" }
  ],
  "phase": "betting",
  "roundNumber": 42
}
```

Implementation: The Pages Function at `functions/api/roulette/status.js` proxies to the roulette worker's DO via a service binding or direct fetch to the worker URL with a special path (`/status`).

---

## Database Schema

### New Migration: `migrations/0020_roulette.sql`

```sql
CREATE TABLE IF NOT EXISTS roulette_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  spins_played INTEGER NOT NULL DEFAULT 0,
  total_wagered INTEGER NOT NULL DEFAULT 0,
  total_won INTEGER NOT NULL DEFAULT 0,
  net_profit INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_roulette_results_date ON roulette_results(date);
CREATE INDEX IF NOT EXISTS idx_roulette_results_user_date ON roulette_results(user_id, date);
```

### Balance Sync Mechanism

Roulette shares the **same `blackjack_sessions` row** for balance:

1. **On bet placement:** Read `blackjack_sessions.session_state.balance`, validate sufficient funds, deduct bet amount, write back. (Same pattern as blackjack MP `place_bet`.)
2. **On result/payout:** Read session, add winnings to balance, write back.
3. **On join:** Read current balance from `blackjack_sessions` (or create default $100 session if none exists for today).

The `session_state` JSON in `blackjack_sessions` already has a `balance` field. Roulette reads and writes ONLY the `balance` field — it does NOT touch `deck`, `playerHand`, etc.

### Leaderboard Integration

The `roulette_results` table accumulates daily stats per player. The leaderboard query combines both:

```sql
-- Daily leaderboard (combined casino)
SELECT u.name as nickname,
  COALESCE(bj.profit, 0) + COALESCE(rl.net_profit, 0) as profit,
  COALESCE(bj.hands_played, 0) as hands_played,
  COALESCE(rl.spins_played, 0) as spins_played
FROM users u
LEFT JOIN (
  -- blackjack profit (existing logic)
  SELECT user_id, (final_balance - 100) as profit, hands_played
  FROM blackjack_results WHERE date = ?
  UNION ALL
  SELECT user_id, (json_extract(session_state, '$.balance') - 100) as profit,
         json_extract(session_state, '$.handsPlayed') as hands_played
  FROM blackjack_sessions WHERE date = ?
    AND NOT EXISTS (SELECT 1 FROM blackjack_results br2
                    WHERE br2.user_id = blackjack_sessions.user_id AND br2.date = ?)
) bj ON u.id = bj.user_id
LEFT JOIN roulette_results rl ON u.id = rl.user_id AND rl.date = ?
WHERE bj.user_id IS NOT NULL OR rl.user_id IS NOT NULL
ORDER BY profit DESC
LIMIT 50
```

**Important:** The combined profit for leaderboard is derived from `blackjack_results/sessions` (which already reflects roulette balance changes since they share the same balance). The `roulette_results` table is for **stats display only** (spins played, total wagered). The profit calculation comes from the shared balance difference from $100 starting.

Actually, simpler approach: Since both games share the SAME balance in `blackjack_sessions`, the existing leaderboard query already captures combined profit (balance - 100 includes roulette gains/losses). We only need `roulette_results` for the "spins played" stat display. The leaderboard query stays almost the same — just add spins_played from `roulette_results` as an extra column.


---

## Frontend Screens & Widgets

### File Structure

```
frontend/lib/blackjack/
├── blackjack_lobby_screen.dart    ← RENAME to casino_lobby_screen.dart
├── blackjack_screen.dart          (unchanged)
├── blackjack_mp_screen.dart       (unchanged)
└── roulette/
    ├── roulette_screen.dart       Main roulette game screen
    ├── roulette_websocket.dart    WebSocket client (pattern from chess/pvp_websocket.dart)
    ├── widgets/
    │   ├── roulette_wheel.dart    Animated wheel widget
    │   ├── betting_table.dart     Clickable betting grid
    │   ├── bet_chips.dart         Chip placement visuals
    │   ├── player_list.dart       Connected players + their bets
    │   ├── phase_timer.dart       Countdown timer bar
    │   └── result_overlay.dart    Win/loss animation overlay
    └── models/
        └── roulette_state.dart    Data classes for bets, game state
```

### Casino Lobby Changes (`casino_lobby_screen.dart`)

Rename `BlackjackLobbyScreen` → `CasinoLobbyScreen`. The lobby uses a **toggle-based layout** — modelled on Chess.IT's Normal/Phantom toggle — to switch between Blackjack and Roulette content within the same screen.

```
┌────────────────────────────────────┐
│  Casino Lobby                      │
├────────────────────────────────────┤
│  [Status Card: shared balance/profit] │  ← ALWAYS visible
│                                    │
│  [ Blackjack ] [ Roulette ]  ← toggle (pill-shaped, highlighted when selected)
│                                    │
│  ====== When Blackjack selected ====== │
│  [▶ Play Solo]                     │
│  [👥 Play with Friends]             │
│  ── Open Tables ──                  │
│  | Alice's table | 2/4 | [Join] |  │
│  | Bob's table   | 3/4 | [Join] |  │
│                                    │
│  ====== When Roulette selected ======= │
│  [🎰 Join Roulette Table]           │
│  ── Players at Table ──             │
│  🟢 Mekhail                        │
│  🟢 Sarah                          │
│  🟢 Bob                            │
│  (or "Table is empty — be the first to play!")
│                                    │
├────────────────────────────────────┤
│  ── Casino Leaderboard ──           │  ← ALWAYS visible
│  [Daily] [Monthly]                 │
│  (combined blackjack + roulette)   │
└────────────────────────────────────┘
```

**Layout structure:**
1. **Status card** (shared balance/profit) — always visible at the top regardless of selected tab.
2. **Toggle row** — pill-shaped buttons `[ Blackjack ]` and `[ Roulette ]`, styled like Chess.IT's Normal/Phantom toggle. The selected button is highlighted. Default tab: **Blackjack**.
3. **Tab content** — switches between Blackjack content and Roulette content based on selected tab.
4. **Casino Leaderboard** — always visible at the bottom regardless of selected tab. Shows Daily/Monthly tabs. Displays combined blackjack + roulette profit, with "spins" column for players with roulette activity.

**Blackjack tab content** (unchanged from current lobby):
- Play Solo button
- Play with Friends button
- Open Tables list

**Roulette tab content:**
- "Join Roulette Table" button — big and prominent, same style as Play Solo button, with red accent. If the user has cashed out today, the button is disabled and shows "Already Cashed Out Today" (same pattern as the existing Blackjack cashout-disabled state).
- "Players at Table" section below the button — shows names of currently connected players, polled from `/api/roulette/status` every 5 seconds. Each player shown with a green circle indicator (🟢). If the table is empty, shows "Table is empty — be the first to play!" instead.

### Roulette Screen (`roulette_screen.dart`)

Main game screen layout (portrait-optimized for mobile, max-width 500px like blackjack):

```
┌─────────────────────────────┐
│ ← Back    Roulette    $85   │  Header: back button, title, balance
├─────────────────────────────┤
│                             │
│      [ WHEEL WIDGET ]       │  Animated wheel (200x200px area)
│       Winning: 17 ●        │  Shows last result below wheel
│                             │
├─────────────────────────────┤
│  ⏱ Betting: 14s remaining  │  Phase timer bar (green countdown)
├─────────────────────────────┤
│                             │
│   [ BETTING TABLE GRID ]    │  Clickable number grid + outside bets
│                             │
│   0                         │
│   1  2  3                   │
│   4  5  6                   │
│   ...                       │
│   34 35 36                  │
│   [RED] [BLACK]             │
│   [ODD] [EVEN]             │
│   [LOW] [HIGH]             │
│                             │
├─────────────────────────────┤
│  Your bets: $5 on Red,      │  Current bet summary
│  $10 on 17                  │
│  Total: $15  [Clear All]    │
├─────────────────────────────┤
│  Players: Mekhail, Sarah    │  Player list + their total bet amounts
│  Sarah: $10 on Black        │
└─────────────────────────────┘
```

### Bet Placement Flow

1. Player taps a number or outside bet area
2. A chip amount selector appears (preset: $1, $5, $10, $25)
3. Player taps chip amount → bet is placed immediately (sent via WebSocket)
4. Chip visually appears on the table at that position
5. Player can tap same spot again to add more
6. "Clear All" removes all bets for this round (refunds to balance)


---

## Wheel Animation Approach

### Design

The wheel is a **CustomPainter** widget that draws the 37 pockets in a circle. The animation is purely visual — the winning number is determined server-side and sent to the client at the start of the SPINNING phase.

### Implementation

```dart
class RouletteWheel extends StatefulWidget {
  final int? winningNumber;  // null during betting, set during spinning
  final String phase;        // 'betting', 'spinning', 'result'
}
```

**Animation sequence (when phase changes to 'spinning'):**

1. **Start rotation:** Wheel rotates using `AnimationController` with a `CurvedAnimation` (ease-out curve)
2. **Calculate target angle:** Given the winning number, compute the final angle where that pocket aligns with the ball indicator (top of wheel)
3. **Spin duration:** 4 seconds of rotation (multiple full rotations + final position)
4. **Easing:** Fast start, gradual slowdown — `Curves.easeOutCubic` over 4s
5. **Ball indicator:** A small circle/arrow at the top of the wheel (fixed position). The wheel rotates underneath it.

**Pocket layout** (European wheel order):
```dart
const wheelOrder = [
  0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36,
  11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9,
  22, 18, 29, 7, 28, 12, 35, 3, 26
];
```

**Color mapping:**
```dart
const redNumbers = {1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36};
// Black = 1-36 minus red. Zero = green.
```

### Rendering

- **Wheel:** Circle divided into 37 colored arcs (red/black/green)
- **Numbers:** Text painted on each arc (white text, rotated to match arc angle)
- **Ball pointer:** Fixed triangle/diamond at top of wheel frame
- **During BETTING:** Wheel is static, showing last result position
- **During SPINNING:** Wheel rotates with animation
- **During RESULT:** Wheel stopped, winning pocket highlighted with glow/pulse animation

### Performance

- Use `RepaintBoundary` around the wheel to avoid redrawing the whole screen
- Pre-calculate pocket angles (each pocket = 360/37 ≈ 9.73°)
- The wheel image could also be a pre-rendered PNG that just rotates (simpler, less CPU) — fallback option if CustomPainter performance is poor on low-end devices


---

## Edge Cases

### Player joins mid-spin
- Server sends `game_state` with `phase: "spinning"` and `winningNumber`
- Client starts the spin animation from a shorter duration (remaining time)
- Player cannot place bets until next BETTING phase

### Player joins during RESULT phase
- Server sends `game_state` with `phase: "result"` and last result info
- Client shows the result briefly, then transitions to BETTING when the phase changes

### Player disconnects mid-bet
- Bets already placed stay — they were already deducted from balance
- When RESULT phase fires, payouts are calculated for all bets (even from disconnected players)
- Payouts are written to D1 regardless of connection status
- On reconnect, player sees updated balance

### Insufficient balance
- Server validates on each `place_bet` message
- If balance < bet amount, server sends `error` message, bet is rejected
- Client should also pre-validate locally to avoid round-trips (but server is authoritative)

### Player is in blackjack AND roulette
- Allowed! Both games read/write the same `blackjack_sessions.balance`
- Each game deducts on bet, credits on win
- Race condition mitigation: D1 operations are serialized per-row. The DO reads fresh balance from D1 on each bet placement (not cached). If a blackjack hand just took the balance to $0, the next roulette bet will fail with "Insufficient balance."

### Table is empty (no players)
- The game loop STOPS (no alarm set)
- When first player connects → immediately enter BETTING phase, set 20s alarm
- This avoids pointless DO alarm cycling with nobody playing

### All players leave during BETTING
- If no bets placed: cancel the round, stop the loop
- If some bets placed: round continues (bets resolve, payouts written to D1 even though players disconnected)

### Cashout interaction
- If a player has cashed out today (`blackjack_results` row exists), they CANNOT place bets
- They CAN still join the table and watch (spectator mode)
- Server checks cashout status on each `place_bet`

### Maximum bet
- No explicit max bet (balance is the natural cap at $100 starting)
- Multiple bets per round are allowed (e.g., $5 on red + $10 on 17)
- Total bets for a round cannot exceed current balance

### Clock sync
- Server sends `timeRemaining` in milliseconds with each phase change
- Client uses this to drive the countdown timer
- Small network latency (<100ms for office users) is acceptable — no NTP sync needed

---

## Design Decisions

### 1. Single Durable Object vs. per-session DOs
**Choice:** Single DO keyed `"roulette-main"`
**Rationale:** There's only one table. No need for per-game instances like blackjack MP. Simpler routing, simpler state. ~38 users is well within a single DO's capacity.

### 2. Alarm-based loop vs. setTimeout
**Choice:** Durable Object alarms
**Rationale:** `setTimeout` in DOs is unreliable — if the DO is evicted from memory, timeouts are lost. Alarms persist across evictions and are the recommended pattern for periodic work in Durable Objects.

### 3. Winning number sent at spin start (not end)
**Choice:** Send winning number in the `spinning` message
**Rationale:** The client needs to know WHERE the wheel should stop to animate correctly. The animation is purely cosmetic — the outcome is already determined. This is standard for online roulette. Players can't exploit knowing the number 5s early because betting is already closed.

### 4. Shared balance via existing blackjack_sessions
**Choice:** Read/write the same row, same `balance` field
**Rationale:** Simplest approach. No new balance tables. The leaderboard already works off this balance. Both games just deduct on bet and credit on win. D1's serialization prevents double-spend.

### 5. Separate roulette_results table (not combining into blackjack_results)
**Choice:** New `roulette_results` table for stats
**Rationale:** Different stats (spins vs. hands, no "blackjacks" field). Keeps the schema clean. The leaderboard profit calculation still comes from the shared balance, so the results table is just for display stats.

### 6. Bet deduction timing
**Choice:** Deduct immediately on bet placement (during BETTING phase)
**Rationale:** Same pattern as blackjack MP. Prevents over-betting. If a player places $5 on red and then $5 on black, both are immediately deducted ($10 total). This is the standard casino model.

### 7. No lobby game listing (unlike blackjack MP)
**Choice:** Single "Join Roulette Table" button + player count indicator
**Rationale:** There's only one table — no need for a game list. The lobby just shows who's there and lets you join.

---

## Tasks

### Backend
1. Create `src/roulette-worker.js` with `RouletteTable` Durable Object — **L**
   - State machine (betting/spinning/result phases)
   - Alarm-based loop
   - WebSocket management (join, leave, reconnect)
   - Bet validation and placement
   - RNG for winning number
   - Payout calculation
   - D1 balance read/write
   - D1 roulette_results upsert
   - `/status` HTTP endpoint for lobby polling
2. Create `wrangler-roulette-worker.toml` — **S**
3. Create `migrations/0020_roulette.sql` — **S**
4. Add Pages Function `functions/api/roulette/status.js` — proxies to worker — **S**
5. Update `functions/api/blackjack/leaderboard.js` to include roulette spins in display — **M**

### Frontend
6. Rename `blackjack_lobby_screen.dart` → `casino_lobby_screen.dart`, add roulette section — **M**
   - Add roulette player indicator (poll `/api/roulette/status` every 5s)
   - Add "Join Roulette Table" button
   - Update leaderboard display to show spins
7. Create `roulette_websocket.dart` — WebSocket client — **S**
   - Connect/disconnect/reconnect logic (mirror chess pattern)
   - Message serialization
8. Create `roulette_screen.dart` — main game screen — **L**
   - Phase display (timer bar, phase indicator)
   - Player list
   - Balance display
   - Bet summary
   - Integration with WebSocket and child widgets
9. Create `roulette_wheel.dart` — animated wheel widget — **L**
   - CustomPainter for 37-pocket wheel
   - Spin animation with easing
   - Result highlight animation
10. Create `betting_table.dart` — clickable bet grid — **M**
    - Number grid (0-36 in standard layout)
    - Outside bet areas (red/black, odd/even, high/low)
    - Chip amount selector
    - Visual chip placement on bets
    - Other players' bets shown (smaller/dimmer chips)
11. Create `result_overlay.dart` — win/loss animations — **S**
12. Create `roulette_state.dart` — data models — **S**
13. Update navigation (main.dart or wherever blackjack lobby is launched) to use new `CasinoLobbyScreen` — **S**

### Deployment
14. Deploy roulette worker: `npx wrangler deploy --config wrangler-roulette-worker.toml` — **S**
15. Run migration: `npx wrangler d1 execute fuseit-wordle-db --file=migrations/0020_roulette.sql --remote` — **S**
16. Update README with roulette redeploy command — **S**

---

## Open Questions

None — all requirements confirmed. Ready for implementation.

