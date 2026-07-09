# Review — blackjack-multiplayer

## Simplification Summary

No simplification pass was run on the source files — the code is generally well-structured and readable, matching the project's existing patterns. The issues found are all correctness or protocol bugs rather than style problems. Making structural edits before the bugs are fixed risks masking the problems.

---

## Issues

### [CRITICAL] `dealer_turn` message fields never match Flutter handler

**File**: `frontend/lib/blackjack/blackjack_mp_screen.dart` case `'dealer_turn'` (~line 191) vs `src/blackjack-mp-worker.js` `dealerTurn()` (~line 694)

The server broadcasts:
```js
{ type: 'dealer_turn', cards: [...], finalHand: [...], finalValue: N }
```

The Flutter handler checks `data['dealer']` first (absent), then falls back to `data['hand']` and `data['value']` (also absent). Neither `cards`, `finalHand`, nor `finalValue` are consumed. The dealer area never updates when the dealer plays out their hand — players see the hidden-card state frozen until the next `game_state` snapshot.

**Fix**: Either align the server payload to `{ type: 'dealer_turn', hand: [...], value: N }`, or update the Flutter handler to read `data['finalHand']` / `data['finalValue']`:
```dart
case 'dealer_turn':
  setState(() {
    final hand = data['finalHand'] ?? data['hand'] ?? data['cards'];
    final value = data['finalValue'] ?? data['value'];
    if (hand != null) _dealer['hand'] = List<Map<String, dynamic>>.from(hand);
    if (value != null) _dealer['value'] = value;
    _phase = 'dealer_turn';
  });
  break;
```

---

### [CRITICAL] `round_result` balance field mismatch — balance never updates after round

**File**: `frontend/lib/blackjack/blackjack_mp_screen.dart` case `'round_result'` (~line 203)

Server sends `newBalance` in each result object:
```js
results.push({ userId, name, outcome, payout, newBalance });
```

Flutter reads `result['balance']`:
```dart
if (idx != -1 && result['balance'] != null) {   // always null
```
and:
```dart
if (rId == widget.userId && result['balance'] != null) {  // always null
  _myBalance = result['balance'];
```

`_myBalance` is never updated after a round. The displayed balance stays at the pre-round value permanently.

**Fix**: Read `result['newBalance']` instead of `result['balance']`. Or rename the server field to `balance` for consistency — but whichever side changes, they must match.

---

### [CRITICAL] `cards_dealt` handler clobbers non-betting players

**File**: `frontend/lib/blackjack/blackjack_mp_screen.dart` case `'cards_dealt'` (~line 113)

```dart
case 'cards_dealt':
  setState(() {
    final dealtPlayers = data['players'];
    if (dealtPlayers != null) {
      _players = List<Map<String, dynamic>>.from(dealtPlayers);  // full replacement
    }
```

The server only includes `bettingPlayers` in `cards_dealt.players` — players who didn't place a bet are excluded. After this assignment, all non-betting players disappear from the client's `_players` list. Their seat widgets vanish and they cannot rejoin the player list without a full `game_state` snapshot.

**Fix**: Merge dealt cards into the existing player list rather than replacing it:
```dart
case 'cards_dealt':
  setState(() {
    final dealtPlayers = data['players'] as List? ?? [];
    for (final dealt in dealtPlayers) {
      final idx = _players.indexWhere((p) => p['userId'] == dealt['userId']);
      if (idx != -1) {
        _players[idx] = Map<String, dynamic>.from(_players[idx])
          ..addAll(Map<String, dynamic>.from(dealt));
      }
    }
    if (data['dealer'] != null) {
      _dealer = Map<String, dynamic>.from(data['dealer']);
    }
    _phase = 'playing';
  });
  break;
```

---

### [CRITICAL] `getToday()` date mismatch between DO worker and D1 sessions

**File**: `src/blackjack-mp-worker.js` line ~57

The DO worker defines its own `getToday()` that always returns the raw UTC date:
```js
function getToday() {
  return new Date().toISOString().split('T')[0];
}
```

But `src/db.js` `getToday()` maps weekends to the preceding Friday:
```js
export function getGameDate(date) {
  const day = date.getUTCDay();
  if (day === 0) date.setUTCDate(date.getUTCDate() - 2); // Sun → Fri
  else if (day === 6) date.setUTCDate(date.getUTCDate() - 1); // Sat → Fri
  return date.toISOString().split('T')[0];
}
```

On Saturday or Sunday, the solo game reads and writes the Friday row in `blackjack_sessions`, but the multiplayer DO reads and writes Saturday/Sunday rows. This creates a separate session with its own $100 balance — players can double-dip each weekend, and the solo leaderboard/cashout won't see MP hands played on weekends.

**Fix**: Export a `getGameDate` helper from a shared module that both Pages Functions and the DO worker can import (or inline the weekend-mapping logic into the DO's `getToday()`):
```js
function getToday() {
  const date = new Date();
  const day = date.getUTCDay();
  if (day === 0) date.setUTCDate(date.getUTCDate() - 2);
  else if (day === 6) date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().split('T')[0];
}
```

---

### [CRITICAL] `player_doubled` handler reads `data['bet']` — server sends `data['newBet']`

**File**: `frontend/lib/blackjack/blackjack_mp_screen.dart` case `'player_doubled'` (~line 169)

```dart
updated['bet'] = data['bet'] ?? updated['bet'];  // 'bet' is null
```

Server sends:
```js
{ type: 'player_doubled', userId, card, hand, value, newBet }
```

The bet amount on the doubling player's seat never updates in the UI.

**Fix**: Read `data['newBet']`:
```dart
updated['bet'] = data['newBet'] ?? data['bet'] ?? updated['bet'];
```

---

### [CRITICAL] `_handleLeave` game-over condition is logically impossible

**File**: `src/blackjack-mp-worker.js` `_handleLeave()` (~line 480)

```js
if (state.players.filter(p => !p.pendingLeave).length === 0 && state.players.length === 0) {
```

`state.players.length === 0` implies the filter result is also 0, but the filter on the left side is 0 only when all remaining players have `pendingLeave = true` (while `state.players` is non-empty). The two conditions are mutually exclusive for the intended "all gone" check. The game is never marked `finished` from the `leave` handler.

**Fix**:
```js
if (state.players.filter(p => !p.pendingLeave).length === 0) {
```
This fires when every player still tracked has a pending leave — i.e. nobody is actively at the table.

---

### [IMPORTANT] `player_joined` handler builds incomplete player object

**File**: `frontend/lib/blackjack/blackjack_mp_screen.dart` case `'player_joined'` (~line 96)

```dart
case 'player_joined':
  setState(() {
    final newPlayer = Map<String, dynamic>.from(data['player'] ?? data);
```

Server sends a flat message `{ type, userId, name, seatIndex }` with no `player` sub-object. The `data['player'] ?? data` fallback uses the raw message, so `newPlayer` has `type`, `userId`, `name`, `seatIndex` but is missing `hand`, `value`, `status`, `bet`, `balance`, `hasActed`, and `disconnected`. The seat widget renders for this player but `_buildPlayerSeat` will show null/default values for every field except name.

**Fix**: Construct a full skeleton for the new player:
```dart
case 'player_joined':
  setState(() {
    final newPlayer = <String, dynamic>{
      'userId': data['userId'],
      'name': data['name'],
      'seatIndex': data['seatIndex'] ?? _players.length,
      'balance': 0,
      'bet': 0,
      'hand': <dynamic>[],
      'value': 0,
      'status': 'waiting',
      'disconnected': false,
    };
    if (!_players.any((p) => p['userId'] == newPlayer['userId'])) {
      _players.add(newPlayer);
    }
  });
  break;
```

---

### [IMPORTANT] `canDouble` from `turn_start` is ignored — double enabled incorrectly client-side

**File**: `frontend/lib/blackjack/blackjack_mp_screen.dart` `_buildPlayActions()` (~line 596)

```dart
final canDouble = hand.length == 2;  // ignores server's canDouble
```

The server sets `canDouble: !next.hasActed` in `turn_start`. After a player hits (and thus `hasActed = true`), the server correctly forbids double, but the client re-enables it whenever the player somehow has exactly 2 cards. The `canDouble` field in `turn_start` is tracked nowhere in state.

**Fix**: Store `canDouble` from `turn_start` in widget state:
```dart
bool _canDouble = false;
// in turn_start handler:
_canDouble = data['canDouble'] ?? false;
// in _buildPlayActions:
final canDouble = _canDouble;
```

---

### [IMPORTANT] Hole card revealed during `betting` phase in `game_state` snapshot

**File**: `src/blackjack-mp-worker.js` `getGameStateFor()` (~line 884)

```js
const hidingHole = state.phase === 'playing';
```

The hole card is only masked during the `playing` phase. If a reconnecting player joins during the `betting` phase (after `startDealing` has already been called but before the first `turn_start` fires — a brief window), `game_state` will expose the dealer's hole card. More relevantly: during `dealer_turn` phase the state snapshot sent on reconnect correctly reveals all cards, which is right. But the check should also cover the narrow gap.

Separately, when `startDealing` transitions directly to `dealer_turn` (all-blackjack scenario) and the `game_state` broadcast fires, `hidingHole` is false and the dealer's second card is briefly visible.

**Fix**: Widen the mask to cover `betting` and `playing` phases:
```js
const hidingHole = ['betting', 'playing'].includes(state.phase) && state.dealer.hand.length > 0;
```

---

### [IMPORTANT] `balance_updated` and `round_starting` messages from spec are never sent

**File**: `src/blackjack-mp-worker.js`

The spec defines two server→client messages that are never emitted:
- `balance_updated` — should confirm balance sync to each player after bet deduction
- `round_starting` — should fire when creator sends `start_round`

While `round_starting` is cosmetic (the `betting_phase` message arrives immediately after), `balance_updated` is important: after a player places a bet, their `_myBalance` in the client is never decremented until the next `game_state` snapshot. The client shows the pre-bet balance while the betting UI is visible.

**Fix for `balance_updated`**: After the D1 write in `_handlePlaceBet`, broadcast:
```js
this.broadcast({ type: 'balance_updated', userId, balance: session.balance });
```
And in the Flutter handler update `_myBalance` when `rId == widget.userId`.

---

### [IMPORTANT] `_handleLeave` updates D1 `player_count` using `state.players.length` after mid-round `pendingLeave`

**File**: `src/blackjack-mp-worker.js` `_handleLeave()` (~line 510)

When a player leaves mid-round, they are marked `pendingLeave = true` but remain in `state.players`. The lobby D1 update then runs:
```js
await env.DB.prepare('UPDATE blackjack_mp_games SET player_count = ? WHERE id = ?')
  .bind(state.players.length, state.gameId).run();
```

This writes the *full* count including the pending-leave player, so the lobby still shows e.g. 3/4 even though only 2 active players remain. Players joining from the lobby may find the table effectively one player short.

**Fix**: Count only non-pending players:
```js
const activeCount = state.players.filter(p => !p.pendingLeave).length;
await env.DB.prepare('UPDATE blackjack_mp_games SET player_count = ? WHERE id = ?')
  .bind(activeCount, state.gameId).run();
```

---

### [IMPORTANT] `games.js` — no auth guard on a balance-visible endpoint

**File**: `functions/api/blackjack-mp/games.js`

The endpoint does call `requireAuth` and returns 401 if unauthenticated — this is correct. However, the endpoint exposes a full list of player names and game states to any authenticated user without restriction. This is intentional per the spec (open lobby), but worth confirming it's the desired behaviour for an office of 38 people. No change needed if the spec is correct; flagging for awareness.

---

### [MINOR] `_formatPayout` sign is misleading for push and lose outcomes

**File**: `frontend/lib/blackjack/blackjack_mp_screen.dart` `_formatPayout()` (~line 660)

On a push, `payout = player.bet` (the returned stake), so `_formatPayout` renders it as `+$50`. This looks like a profit. The caller displays it alongside a "Push 🤝" label but the green `+$50` is confusing.

On a loss, `payout = 0` so the display shows `$0` rather than `-$50` (the bet forfeited). The user has no clear indication of how much they lost.

**Fix**: Pass the *net* outcome to the display function rather than the raw payout. In `resolveRound`, compute `netGain = payout - player.bet` and send it alongside `payout`. Or compute it client-side: `final net = payout - (result['bet'] ?? 0)` and format that.

---

### [MINOR] `_buildPlayWithFriendsButton` — cashed-out players can still create a game

**File**: `frontend/lib/blackjack/blackjack_lobby_screen.dart` `_buildPlayWithFriendsButton()` (~line 217)

The `_buildPlayButton` disables the solo play button for cashed-out players. But `_buildPlayWithFriendsButton` is always enabled (only gates on `_mpLoading`). A cashed-out player can create a multiplayer game and join it, then fail to place any bet (the server will reject with "Already cashed out today"). This is not a crash but creates a confusing UX where the button appears active but gameplay is blocked.

**Fix**: Disable the button when `_cashedOut`:
```dart
onPressed: (_mpLoading || _cashedOut) ? null : _createMpGame,
```
And update the label accordingly.

---

### [MINOR] `startDealing` — fresh deck created without shuffle exclusion when deck is low

**File**: `src/blackjack-mp-worker.js` `startDealing()` (~line 558)

```js
if (state.deck.length < needed) {
  state.deck = createDeck();
}
```

This replaces a low deck with a fully fresh shuffled deck at the *start* of a dealing phase, when no cards are yet in play. Because this runs before cards are dealt, there are no in-play cards to exclude — the replacement is safe. However, it's inconsistent with the spec's description of reshuffling *excluding cards in play*, and with the `drawCard` helper's own exclusion logic. If the dealing loop's mid-deal `drawCard` calls hit a zero-length deck, `drawCard` does handle it correctly (with exclusion) — so this is a redundant early check, not a correctness bug. Consider removing the pre-deal check and relying solely on `drawCard`'s internal reshuffle logic.

---

### [NIT] `print` debug statements left in production WebSocket client

**File**: `frontend/lib/blackjack/blackjack_mp_websocket.dart`

Multiple `print(...)` calls remain: connection URL, every received message, reconnection events. These will appear in browser devtools for all 38 users and may reveal game state (hand values, balances) in logs. Remove or gate behind a `kDebugMode` flag — consistent with the chess `pvp_websocket.dart` which has the same issue but is an existing problem.

---

### [NIT] `_buildCard` and `_buildSmallCard` are near-duplicates

**File**: `frontend/lib/blackjack/blackjack_mp_screen.dart`

Two card builders with identical logic but different fixed dimensions (52×72 vs 32×44) and slight style differences. Not a bug, but if card rendering needs to change it must be updated in two places. A single `_buildCard(card, {double width = 52, double height = 72})` widget would suffice.

---

### [NIT] `double` action name collides with Dart keyword

**File**: `frontend/lib/blackjack/blackjack_mp_websocket.dart` line ~56

```dart
void doubleBet() => send({'type': 'double'});
```

`doubleBet` is a fine name but the original spec proposed `double_()`. `doubleBet` is actually better — this is a positive nit, leaving it as-is.

---

## Verdict

**Requires fixes** — 6 Critical issues must be resolved before this is usable in production.

### Must-fix before merge

1. **`dealer_turn` field mismatch** — dealer animation/state never updates on client
2. **`round_result` `newBalance` vs `balance` mismatch** — balance display never updates after any round
3. **`cards_dealt` replaces full player list** — non-betting players disappear from UI each round
4. **`getToday()` date mismatch** — weekend players get a fresh $100 balance in multiplayer, detached from solo session
5. **`player_doubled` `newBet` vs `bet` mismatch** — bet display never updates on double
6. **`_handleLeave` dead condition** — games never marked `finished`, lobby accumulates stale entries forever

Items 1–5 will cause visible runtime bugs in the first play session. Item 6 will cause the lobby to fill with ghost games after the first day of use.
