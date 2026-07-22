# Klond.IT — Daily Solitaire Design Spec

## Overview

A daily Klondike Solitaire (Draw 3) game for Fuse Arcade. Every player gets the same deterministic deck each day. One attempt per day, no undo — skill and strategy matter. Server-side state prevents cheating via refresh. Scoring rewards completion, speed, and efficiency.

## Goals & Non-Goals

**Goals:**
- Classic Klondike Solitaire with Draw 3 rules
- Same deck for all players each day (deterministic seeded shuffle)
- One attempt per day — no restarts, no undo
- Server-validated moves (no client-side cheating)
- Point-based scoring (completion + time + moves)
- Daily and monthly leaderboards
- Tap-to-move interaction (mobile-friendly)
- Auto-move to foundation for obvious plays (Aces)
- Dark theme matching Fuse Arcade aesthetic
- "Give Up" option that still awards participation point

**Non-Goals:**
- Drag-and-drop (too complex on web/mobile, tap-to-move is primary)
- Undo/redo functionality
- Multiple attempts per day
- Hints or auto-solve
- Custom deck themes or card art
- Multiplayer/competitive real-time play
- WebSocket connections (pure REST, single-player)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter Web Frontend                                        │
│  ┌───────────────────┐  ┌─────────────────────────────────┐ │
│  │ Klond.IT Lobby      │  │ Solitaire Game Screen           │ │
│  │ - Today's status   │  │ - Stock + Waste (top-left)      │ │
│  │ - Play button      │→ │ - 4 Foundations (top-right)     │ │
│  │ - Leaderboard      │  │ - 7 Tableau columns             │ │
│  │ - Help (?) button  │  │ - Move counter + timer          │ │
│  │ - Rules dialog     │  │ - Give Up button                │ │
│  └───────────────────┘  └─────────────────────────────────┘ │
└──────────────────────────────┬──────────────────────────────┘
                               │ REST API (Bearer token auth)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  Cloudflare Pages Functions: /api/solitaire/*                │
│  - GET  /today       → get or create today's game state      │
│  - POST /move        → move card(s) between piles            │
│  - POST /draw        → draw 3 from stock                     │
│  - POST /recycle     → flip waste back to stock              │
│  - POST /give-up     → end game, record 1 point             │
│  - GET  /leaderboard → daily + monthly scores                │
└──────────────────────────────┬──────────────────────────────┘
                               │ D1 binding
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  D1 Database (fuseit-wordle-db)                              │
│  - solitaire_sessions (game state JSON, one per user/day)    │
│  - solitaire_results  (completed games for leaderboard)      │
└─────────────────────────────────────────────────────────────┘
```

---

## Database Schema

Migration file: `migrations/0021_solitaire.sql`

```sql
CREATE TABLE IF NOT EXISTS solitaire_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  session_state TEXT NOT NULL DEFAULT '{}',
  started_at TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, date)
);

CREATE TABLE IF NOT EXISTS solitaire_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  completed INTEGER NOT NULL DEFAULT 0,
  moves INTEGER NOT NULL DEFAULT 0,
  time_seconds INTEGER NOT NULL DEFAULT 0,
  points INTEGER NOT NULL DEFAULT 0,
  completed_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_solitaire_results_date ON solitaire_results(date);
CREATE INDEX IF NOT EXISTS idx_solitaire_results_user_date ON solitaire_results(user_id, date);
```


---

## Game State Structure

The `session_state` column stores JSON representing the full game state:

```json
{
  "stock": ["Ah", "2c", "Kd", ...],
  "waste": ["7s", "Qh"],
  "foundations": {
    "hearts": ["Ah", "2h", "3h"],
    "diamonds": [],
    "clubs": ["Ac"],
    "spades": []
  },
  "tableau": [
    { "hidden": [], "visible": ["Kh"] },
    { "hidden": ["3c"], "visible": ["Jd"] },
    { "hidden": ["5s", "2d"], "visible": ["10c"] },
    { "hidden": ["8h", "Qs", "4d"], "visible": ["9s"] },
    { "hidden": ["6c", "7d", "Ah", "3s"], "visible": ["8d"] },
    { "hidden": ["Kc", "2s", "9h", "Jc", "4s"], "visible": ["7h"] },
    { "hidden": ["5d", "6h", "10s", "Qc", "3d", "8c"], "visible": ["6s"] }
  ],
  "moves": 0,
  "status": "in_progress",
  "drawPointer": 0
}
```

### Card Encoding

Cards are encoded as 2-3 character strings: `{rank}{suit_letter}`

- Ranks: `A`, `2`–`10`, `J`, `Q`, `K`
- Suits: `h` (hearts), `d` (diamonds), `c` (clubs), `s` (spades)
- Examples: `"Ah"` = Ace of Hearts, `"10s"` = 10 of Spades, `"Kd"` = King of Diamonds

### Status Values

| Status | Meaning |
|--------|---------|
| `"in_progress"` | Game is active, player can make moves |
| `"won"` | All 52 cards in foundations |
| `"gave_up"` | Player clicked Give Up |

### Card Colors (for alternating-color rule)

- **Red:** hearts (`h`), diamonds (`d`)
- **Black:** clubs (`c`), spades (`s`)


---

## Deterministic Deck Generation

All players get the same deck each day. The deck is shuffled using a seeded PRNG based on the date string.

### Algorithm (in `src/solitaire-deck.js`)

```javascript
// Seeded PRNG (mulberry32)
function mulberry32(seed) {
  return function() {
    seed |= 0; seed = seed + 0x6D2B79F5 | 0;
    let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

// Convert date string to numeric seed
function dateToSeed(dateStr) {
  let hash = 0;
  for (let i = 0; i < dateStr.length; i++) {
    const chr = dateStr.charCodeAt(i);
    hash = ((hash << 5) - hash) + chr;
    hash |= 0;
  }
  return Math.abs(hash);
}

// Generate the deck for a given date
function generateDeck(dateStr) {
  const suits = ['h', 'd', 'c', 's'];
  const ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
  const deck = [];
  for (const suit of suits) {
    for (const rank of ranks) {
      deck.push(rank + suit);
    }
  }
  // Fisher-Yates shuffle with seeded RNG
  const rng = mulberry32(dateToSeed(dateStr));
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

// Deal into initial game state
function dealGame(dateStr) {
  const deck = generateDeck(dateStr);
  const tableau = [];
  let idx = 0;
  for (let col = 0; col < 7; col++) {
    const hidden = deck.slice(idx, idx + col);
    idx += col;
    const visible = [deck[idx]];
    idx++;
    tableau.push({ hidden, visible });
  }
  // Remaining 24 cards go to stock
  const stock = deck.slice(idx);
  return {
    stock,
    waste: [],
    foundations: { hearts: [], diamonds: [], clubs: [], spades: [] },
    tableau,
    moves: 0,
    status: 'in_progress',
    drawPointer: 0
  };
}
```

### Deal Layout

| Column | Hidden cards | Face-up card | Total |
|--------|-------------|--------------|-------|
| 1 | 0 | 1 | 1 |
| 2 | 1 | 1 | 2 |
| 3 | 2 | 1 | 3 |
| 4 | 3 | 1 | 4 |
| 5 | 4 | 1 | 5 |
| 6 | 5 | 1 | 6 |
| 7 | 6 | 1 | 7 |
| **Total** | **21** | **7** | **28** |

Stock gets the remaining 24 cards (52 − 28 = 24).


---

## API Endpoints

All endpoints require `Authorization: Bearer <token>` header. Located at `functions/api/solitaire/`.

### GET /api/solitaire/today

Get or create today's game session.

**Response (no existing session — creates one):**
```json
{
  "status": "in_progress",
  "stock_count": 24,
  "waste_top": null,
  "waste_count": 0,
  "foundations": {
    "hearts": 0, "diamonds": 0, "clubs": 0, "spades": 0
  },
  "tableau": [
    { "hidden": 0, "visible": ["Kh"] },
    { "hidden": 1, "visible": ["Jd"] },
    { "hidden": 2, "visible": ["10c"] },
    { "hidden": 3, "visible": ["9s"] },
    { "hidden": 4, "visible": ["8d"] },
    { "hidden": 5, "visible": ["7h"] },
    { "hidden": 6, "visible": ["6s"] }
  ],
  "moves": 0,
  "elapsed_seconds": 0,
  "started": false
}
```

**Response (already completed):**
```json
{
  "status": "won",
  "points": 20,
  "moves": 74,
  "time_seconds": 112,
  "completed": true
}
```

**Notes:**
- Hidden cards are returned as count only (never reveal to client)
- Visible cards in tableau are the face-up stack (bottom to top)
- `waste_top` shows the playable card(s) from waste (up to 3 most recently drawn, only top is playable)
- `started` is false until first move/draw (timer not running yet)

### POST /api/solitaire/move

Move a card or stack of cards from one location to another.

**Request:**
```json
{
  "from": { "zone": "tableau", "col": 2, "cardIndex": 0 },
  "to": { "zone": "foundation", "suit": "hearts" }
}
```

**Zone types:**
- `"tableau"` — requires `col` (0–6) and `cardIndex` (index within visible array, 0 = bottom)
- `"foundation"` — requires `suit` ("hearts", "diamonds", "clubs", "spades")
- `"waste"` — no additional params (always top card)

**Move `from` zones:** `"tableau"`, `"waste"`
**Move `to` zones:** `"tableau"` (requires `col`), `"foundation"` (requires `suit`)

**Response (success):**
```json
{
  "ok": true,
  "state": { /* same format as GET /today response */ },
  "auto_moved": ["Ah"],
  "won": false
}
```

**Response (invalid move):**
```json
{
  "ok": false,
  "error": "Cannot place red card on red card"
}
```

**Response (game over):**
```json
{
  "ok": true,
  "state": { /* final state */ },
  "won": true,
  "points": 20,
  "time_seconds": 95,
  "moves": 72
}
```

### POST /api/solitaire/draw

Draw up to 3 cards from stock to waste.

**Request:** (empty body)

**Response:**
```json
{
  "ok": true,
  "drawn": ["7s", "Qh", "3d"],
  "stock_count": 21,
  "waste_top": ["3d", "Qh", "7s"],
  "moves": 5
}
```

**Notes:**
- If fewer than 3 cards remain in stock, draws what's available
- If stock is empty, returns error suggesting recycle
- Counts as 1 move

### POST /api/solitaire/recycle

Flip waste pile back to stock (when stock is empty).

**Request:** (empty body)

**Response:**
```json
{
  "ok": true,
  "stock_count": 18,
  "waste_top": null,
  "waste_count": 0,
  "moves": 6
}
```

**Notes:**
- Only valid when stock is empty
- Waste cards go back to stock in reverse order (maintaining draw-3 cycling behavior)
- Counts as 1 move
- Unlimited recycling allowed

### POST /api/solitaire/give-up

End the game voluntarily. Records 1 point for trying.

**Request:** (empty body)

**Response:**
```json
{
  "ok": true,
  "status": "gave_up",
  "points": 1,
  "moves": 34,
  "time_seconds": 245
}
```

### GET /api/solitaire/leaderboard

**Response:**
```json
{
  "daily": [
    { "nickname": "Alice", "points": 20, "moves": 72, "time_seconds": 95, "completed": true },
    { "nickname": "Bob", "points": 14, "moves": 110, "time_seconds": 180, "completed": true },
    { "nickname": "Charlie", "points": 1, "moves": 45, "time_seconds": 300, "completed": false }
  ],
  "monthly": [
    { "nickname": "Alice", "total_points": 280, "games_played": 15, "games_won": 12 },
    { "nickname": "Bob", "total_points": 210, "games_played": 15, "games_won": 9 }
  ],
  "date": "2026-07-16"
}
```


---

## Move Validation Logic

All validation is server-side. The client sends intent, server validates and applies.

### Card Helper Functions

```javascript
function getRank(card) { return card.slice(0, -1); }  // "10h" → "10"
function getSuit(card) { return card.slice(-1); }       // "10h" → "h"
function isRed(card) { return 'hd'.includes(getSuit(card)); }
function isBlack(card) { return 'cs'.includes(getSuit(card)); }

const RANK_ORDER = ['A','2','3','4','5','6','7','8','9','10','J','Q','K'];
function rankValue(card) { return RANK_ORDER.indexOf(getRank(card)); }
```

### Tableau → Tableau Validation

Moving card(s) from one tableau column to another:

1. **Source must have visible cards** at the given `cardIndex`
2. **All cards from `cardIndex` to top** move together (the stack)
3. **Destination rules:**
   - If destination column is empty: only a King (rank 12) can be placed
   - If destination has visible cards: bottom card of moving stack must be one rank lower AND opposite color to destination's top card
4. **After move:** if source column's visible array is now empty and hidden array is non-empty, flip the top hidden card to visible

### Waste → Tableau Validation

1. Waste must have at least one card
2. Top of waste follows same destination rules as tableau-to-tableau (single card)
3. After move: waste top is removed

### Waste → Foundation Validation

1. Waste must have at least one card
2. Card must match foundation suit
3. Card rank must be exactly one above foundation's current top (or Ace if foundation empty)

### Tableau → Foundation Validation

1. Only the top visible card of a tableau column can go to foundation
2. Card must match foundation suit
3. Card rank must be exactly one above foundation's current top (or Ace if foundation empty)
4. After move: if visible becomes empty and hidden is non-empty, flip top hidden card

### Foundation → Tableau Validation (allowed)

1. Top card of a foundation can be moved back to tableau
2. Standard tableau placement rules apply (descending rank, alternating color)
3. This is a valid but rare strategic move

### Draw Validation

1. Stock must have at least 1 card
2. Draw min(3, stock.length) cards from stock → push to waste
3. Counts as 1 move

### Recycle Validation

1. Stock must be empty
2. Waste must have at least 1 card
3. Entire waste is flipped to become new stock (reversed so draw order cycles correctly)
4. Counts as 1 move

### Win Detection

After every successful move to foundation, check:
```javascript
function checkWin(state) {
  const total = Object.values(state.foundations)
    .reduce((sum, pile) => sum + pile.length, 0);
  return total === 52;
}
```

### Auto-Move Logic

After each successful move, check if any obvious auto-moves exist:
- If an Ace is now the top visible card of any tableau column or the top of waste, automatically move it to its foundation
- If a 2 is available and its matching Ace is already in foundation, auto-move it
- Only auto-move when it's **always safe** (Aces and 2s are always safe to auto-move)
- Return list of auto-moved cards in response so client can animate


---

## Scoring System

Points are calculated when a game ends (win or give-up).

```javascript
function calculatePoints(completed, moves, timeSeconds) {
  let points = 0;

  // Completion
  if (completed) points += 10;
  else points += 1;  // tried but didn't finish

  // Time bonus (only if completed)
  if (completed) {
    if (timeSeconds < 120) points += 5;
    else if (timeSeconds < 300) points += 3;
    else if (timeSeconds < 600) points += 1;
  }

  // Moves bonus (only if completed)
  if (completed) {
    if (moves < 80) points += 5;
    else if (moves < 120) points += 3;
    else if (moves < 160) points += 1;
  }

  return points;
}
```

| Category | Condition | Points |
|----------|-----------|--------|
| Completion | Fully solved | 10 |
| Completion | Not solved (tried) | 1 |
| Time | Under 2 min (completed) | 5 |
| Time | Under 5 min (completed) | 3 |
| Time | Under 10 min (completed) | 1 |
| Moves | Under 80 (completed) | 5 |
| Moves | Under 120 (completed) | 3 |
| Moves | Under 160 (completed) | 1 |

**Max:** 20 points (10 + 5 + 5)
**Min (tried):** 1 point
**Not playing:** no entry on leaderboard

---

## Leaderboard Queries

### Daily Leaderboard

```sql
SELECT u.name as nickname, sr.points, sr.moves, sr.time_seconds, sr.completed
FROM solitaire_results sr
JOIN users u ON u.id = sr.user_id
WHERE sr.date = ?
ORDER BY sr.points DESC, sr.time_seconds ASC
LIMIT 50
```

Sorted by: points descending, then time ascending (faster breaks ties).

### Monthly Leaderboard

```sql
SELECT u.name as nickname,
       SUM(sr.points) as total_points,
       COUNT(*) as games_played,
       SUM(sr.completed) as games_won
FROM solitaire_results sr
JOIN users u ON u.id = sr.user_id
WHERE sr.date >= ? AND sr.date <= ?
GROUP BY sr.user_id
ORDER BY total_points DESC, games_won DESC
LIMIT 50
```

Month range: `{YYYY-MM}-01` to today's date.


---

## Frontend Screens & Widgets

### File Structure

```
frontend/lib/solitaire/
├── solitaire_lobby_screen.dart    # Lobby with status, leaderboard, play button
├── solitaire_game_screen.dart     # Main game board
├── widgets/
│   ├── playing_card.dart          # Single card widget (face-up/face-down)
│   ├── card_stack.dart            # Fanned stack of cards (tableau column)
│   ├── foundation_pile.dart       # Foundation pile widget
│   ├── stock_waste.dart           # Stock + waste area widget
│   └── solitaire_help_dialog.dart # Rules/help modal
└── solitaire_service.dart         # API client for solitaire endpoints
```

### Lobby Screen (`solitaire_lobby_screen.dart`)

Layout:
- Title: "Klond.IT" with themed glow
- Status card: "Not started" / "In progress (34 moves)" / "Completed! 18 pts"
- **Play** button (green/`theme.correct`) — disabled if already completed
- **Leaderboard** section with daily/monthly tabs
- **?** help button (top-right)
- **Back** arrow (top-left)

### Game Screen (`solitaire_game_screen.dart`)

Portrait layout optimized for mobile:

```
┌─────────────────────────────────┐
│  ← Back    Moves: 12   ⏱ 1:34  │  ← Header bar
├─────────────────────────────────┤
│  [Stock] [Waste]    [♥][♦][♣][♠]│  ← Stock/Waste + Foundations
├─────────────────────────────────┤
│                                 │
│  [1] [2] [3] [4] [5] [6] [7]   │  ← 7 Tableau columns
│   K   Q   J   10  9   8   7    │     (fanned vertically)
│       J   10  9   8   7   6    │
│           9   8   7   6   5    │
│               7   6   5   4    │
│                   5   4   3    │
│                       3   2    │
│                           A    │
│                                 │
├─────────────────────────────────┤
│        [Give Up]        [?]     │  ← Bottom actions
└─────────────────────────────────┘
```

### Card Widget (`playing_card.dart`)

- **Face-up card:** White/light background, rank + suit displayed, colored pip (red for hearts/diamonds, black for clubs/spades)
- **Face-down card:** Solid `theme.correct` (green) background with subtle pattern
- **Selected card:** Highlighted border using `theme.present` (amber/yellow glow)
- **Card size:** ~50×70px on mobile, responsive scaling
- **Empty slot:** Dashed border outline

### Foundation Pile (`foundation_pile.dart`)

- Outlined rectangle with `theme.correct` border
- Shows suit symbol when empty
- Shows top card when non-empty
- Count badge showing number of cards

### Stock & Waste (`stock_waste.dart`)

- **Stock:** Face-down card pile (shows count). Tap to draw 3.
- **Waste:** Shows top 1-3 cards fanned slightly. Only topmost is tappable.
- When stock is empty: shows a refresh/recycle icon. Tap to recycle.

### Tableau Column (`card_stack.dart`)

- Vertical fan of cards, overlapping (hidden cards show ~15px of back, visible cards show ~25px + full bottom card)
- Hidden cards: face-down styling, non-interactive
- Visible cards: face-up, tappable for selection
- Selected card and all cards below it highlight together

---

## Interaction Design (Tap-to-Move)

### Flow

1. **Tap a card** → it becomes "selected" (amber glow border)
   - If tapping a visible tableau card: selects that card and all cards on top of it
   - If tapping the waste top card: selects it
   - If tapping a foundation top card: selects it (for moving back to tableau)

2. **Tap a destination** → attempt the move
   - Tap an empty tableau slot → move King there
   - Tap the top of a tableau column → move to that column
   - Tap a foundation pile → move to foundation
   - If invalid: show brief error flash, deselect

3. **Tap the same card again** → deselect

4. **Tap stock pile** → draw 3 (no selection needed)

5. **Tap empty stock** → recycle waste to stock

### Auto-Move Shortcuts

- **Tap an Ace** (anywhere): auto-moves to its empty foundation (skip destination tap)
- **Tap a 2** whose Ace is in foundation: auto-moves to foundation
- **Double-tap any card**: attempt auto-move to foundation if valid

### Visual Feedback

- Selected card(s): `theme.present` (amber) border glow, slight lift (scale 1.02)
- Valid destinations: subtle pulse/glow on eligible targets
- Invalid move: brief red flash on the card, shake animation
- Card flip (hidden → visible): flip animation (0.3s)
- Move animation: card slides to destination (0.2s ease-out)


---

## Edge Cases

### Browser Close / Disconnect Mid-Game

- Game state is persisted on every move (each API call updates `session_state`)
- On return, `GET /api/solitaire/today` returns current state
- Timer continues based on `started_at` (wall-clock time, not active time)
- This means closing and coming back later costs time points — intentional to prevent "think overnight" strategies

### Give Up

- Player presses "Give Up" → confirmation dialog → `POST /api/solitaire/give-up`
- Records result with `completed = 0`, current moves, elapsed time
- Awards 1 point (participation)
- Game status changes to `"gave_up"` — no further moves accepted

### Auto-Complete Detection

Not implemented in v1. Player must manually move all remaining cards even if the game is "obviously won." This keeps scoring fair (moves/time still count). Future enhancement could detect when all cards are face-up and no stock remains.

### No Valid Moves (Stuck)

- Server does NOT detect stuck states — player must choose to Give Up
- This is intentional: sometimes a move sequence opens up that isn't obvious

### Same-Day Multiple Requests

- `GET /today` is idempotent — returns existing session if one exists
- If `solitaire_results` entry exists for today, returns completed state
- Cannot start a new game on same day after completion/give-up

### Timer Logic

- `started_at` is set on the **first action** (first draw, first move)
- Not set on `GET /today` (viewing the board doesn't start timer)
- `time_seconds` on completion = `now - started_at` in seconds
- Displayed to user as `MM:SS` format in the game header

### Weekend Handling

- Uses existing `getToday()` / `getGameDate()` from `src/db.js`
- Weekends map to Friday's date (consistent with other games)

---

## Help Dialog Content

Title: **How to Play Klond.IT**

```
🃏 GOAL
Move all 52 cards to the four foundation piles, 
building each suit up from Ace to King.

📋 RULES
• Tableau: Build down in alternating colors 
  (red on black, black on red)
• Foundation: Build up by suit (A → 2 → 3 → ... → K)
• Stock: Tap to draw 3 cards. Only the top drawn card 
  is playable.
• Empty columns: Only a King can fill an empty column
• Move stacks: You can move a sequence of face-up cards 
  together if they follow the alternating-color rule

🎮 CONTROLS
• Tap a card to select it (amber highlight)
• Tap a destination to move it there
• Tap the stock pile to draw 3 cards
• Tap the empty stock to recycle the waste pile
• Aces auto-move to foundations when tapped

⚡ DAILY CHALLENGE
• Same deck for everyone — compare your skills!
• One attempt per day — no undo, no restart
• Timer starts on your first move

🏆 SCORING (max 20 points)
• Completed: 10 pts | Tried: 1 pt
• Under 2 min: +5 | Under 5 min: +3 | Under 10 min: +1
• Under 80 moves: +5 | Under 120: +3 | Under 160: +1
```

---

## Design Decisions

### 1. "Klond.IT" as the name
**Choice:** "Klond.IT" over "Soli.IT" or "Stack.IT"
**Rationale:** "Deal" is a card-specific verb (dealing cards), fits the .IT pattern naturally, and avoids confusion with "Stack.IT" which could imply a different game. "Soli.IT" sounds awkward spoken aloud.

### 2. Tap-to-move over drag-and-drop
**Choice:** Tap-to-move as primary (and only) interaction
**Rationale:** Flutter web drag-and-drop has notorious issues on mobile browsers (ghost images, scroll interference, touch event conflicts). Tap-to-move works identically on desktop and mobile, is easier to implement, and is less error-prone for users with imprecise touches.

### 3. Server-side state validation
**Choice:** All game logic on server, client is display-only
**Rationale:** Prevents cheating (can't manipulate state via devtools), ensures fair leaderboard, consistent with the "daily challenge for office bragging rights" model. The ~38 users won't stress the D1 database even with per-move writes.

### 4. Wall-clock timer (not active time)
**Choice:** Timer runs from first move until completion, regardless of tab visibility
**Rationale:** Simpler to implement (just store `started_at`), prevents gaming by closing tab to "pause." Consistent pressure. If you step away, you lose time points — play when you're ready.

### 5. No undo
**Choice:** Mistakes are permanent
**Rationale:** Core design requirement. Creates tension and rewards careful play. "Learn and try again tomorrow" builds daily engagement.

### 6. Unlimited stock recycling
**Choice:** Allow unlimited passes through the stock
**Rationale:** Standard Klondike Draw-3 rules. Without unlimited recycling, many deals become unsolvable, which would frustrate daily players. The move counter still penalizes excessive recycling.

### 7. Auto-move only Aces and 2s
**Choice:** Only auto-move the safest cards (Aces, 2s)
**Rationale:** Moving higher cards to foundation can be strategically wrong (you might need them in tableau). Auto-moving only Aces/2s is universally safe and saves tedious taps without removing strategic depth.

### 8. Foundation → Tableau allowed
**Choice:** Allow pulling cards back from foundation to tableau
**Rationale:** Standard Klondike rules allow this. Sometimes you need to move a card from foundation back to tableau to unblock a sequence. Removes a frustration point for skilled players.

---

## Tasks

1. **Create `src/solitaire-deck.js`** — Seeded PRNG, deck generation, deal function — S
2. **Create migration `migrations/0021_solitaire.sql`** — DB tables and indexes — S
3. **Create `functions/api/solitaire/today.js`** — GET endpoint, create/return session — M
4. **Create `functions/api/solitaire/move.js`** — POST endpoint, validate + apply moves, auto-move, win detection — L
5. **Create `functions/api/solitaire/draw.js`** — POST endpoint, draw from stock — S
6. **Create `functions/api/solitaire/recycle.js`** — POST endpoint, recycle waste to stock — S
7. **Create `functions/api/solitaire/give-up.js`** — POST endpoint, end game, calculate score — S
8. **Create `functions/api/solitaire/leaderboard.js`** — GET endpoint, daily + monthly queries — M
9. **Create `frontend/lib/solitaire/solitaire_service.dart`** — API client — M
10. **Create `frontend/lib/solitaire/solitaire_lobby_screen.dart`** — Lobby UI, status, leaderboard — M
11. **Create `frontend/lib/solitaire/solitaire_game_screen.dart`** — Game board, state management, tap-to-move logic — L
12. **Create `frontend/lib/solitaire/widgets/playing_card.dart`** — Card widget (face-up/down/selected) — M
13. **Create `frontend/lib/solitaire/widgets/card_stack.dart`** — Tableau column with fanned cards — M
14. **Create `frontend/lib/solitaire/widgets/foundation_pile.dart`** — Foundation pile widget — S
15. **Create `frontend/lib/solitaire/widgets/stock_waste.dart`** — Stock + waste area — S
16. **Create `frontend/lib/solitaire/widgets/solitaire_help_dialog.dart`** — Help/rules modal — S
17. **Wire into main menu** — Add Klond.IT card to 'Classic Games' section, route to lobby — S
18. **Add CORS handler** — `onRequestOptions` export in each endpoint — S

---

## Open Questions

1. **Should we add auto-complete?** When all cards are face-up and stock is empty, auto-move everything to foundations with animation? (Nice UX but adds complexity — defer to v2?)
2. **Should "Give Up" require confirmation?** Probably yes (accidental taps) — but adds a dialog step.
3. **Should the leaderboard show in-progress games?** Currently only shows completed/gave-up results. Could show "in progress" indicator for active players to build suspense.
