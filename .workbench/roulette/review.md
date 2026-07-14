# Review — roulette

## Simplification Summary
No simplification pass performed — the files are already clear and consistent with the project's conventions. Logic correctness issues were found that take priority.

---

## Issues

### [CRITICAL] `ROULETTE_TABLE` DO binding missing from Pages `wrangler.toml`
**File**: `wrangler.toml`

`functions/api/roulette/status.js` calls `env.ROULETTE_TABLE.idFromName(...)` but `wrangler.toml` (the Pages project config) has no binding for the roulette worker's DO. The four other workers (Invade, Pong, Chess, Blackjack) all appear as `[[durable_objects.bindings]]` entries with a `script_name` referencing their deployed worker. The roulette binding is absent.

At runtime the Pages Function will throw `env.ROULETTE_TABLE is undefined` and the status endpoint will fall back to returning `{ players: [], phase: 'idle', roundNumber: 0 }` for every request — the lobby will always show an empty table regardless of who is actually playing.

**Fix**: Add to `wrangler.toml`:
```toml
[[durable_objects.bindings]]
name = "ROULETTE_TABLE"
class_name = "RouletteTable"
script_name = "fuseit-roulette-worker"
```

---

### [CRITICAL] `result` message missing `yourNewBalance` — client balance never updates on win
**File**: `src/roulette-worker.js:509` / `frontend/lib/blackjack/roulette/roulette_screen.dart:183`

The server broadcasts:
```json
{ "type": "result", "winningNumber": 17, "winningColor": "black", "payouts": [...] }
```
The client reads `data['yourNewBalance']` but that field is not in the message. The spec (`phase_change — RESULT`) requires it as a top-level field alongside `payouts`. Without it, `_balance` is never updated on the winning player's screen (the `?? _balance` fallback keeps the old value).

The winning player's `newBalance` is inside `payouts`, but the client would have to find their own entry there — it currently doesn't do that for the balance display.

**Fix (server)**: Add `yourNewBalance` per-recipient, or broadcast each player's result individually. Simplest: change the broadcast to send each player their own message:
```js
for (const payout of payouts) {
  const ws = this.ctx.getWebSockets().find(...)
  // send payout + yourNewBalance to that specific socket
}
// then broadcast summary to all
```
Or add the relevant `newBalance` to each payout entry (it's already there) and update the Flutter client to read it from `payouts`:
```dart
case 'result':
  final myPayout = (data['payouts'] as List?)
      ?.cast<Map<String, dynamic>>()
      .firstWhere((p) => p['userId'] == widget.userId, orElse: () => {});
  _balance = myPayout?['newBalance'] ?? _balance;
```

---

### [CRITICAL] Losing players' `player.balance` in DO state not updated after result
**File**: `src/roulette-worker.js:466`

The payout loop only touches D1 and updates `player.balance` when `totalWon > 0`. If a player loses all bets (totalWon == 0), their `player.balance` in DO state is never decremented — it still reflects the pre-bet amount, not the post-deduction amount. Bets were already deducted from D1 on placement, so D1 is correct; but DO state is stale.

On the next round's `getGameState` a fresh D1 read corrects it, so this is ultimately harmless for balance accuracy. However the `payouts` array that goes to the client contains the stale `player.balance` as `newBalance` for losing players — they see the wrong number in the result overlay.

**Fix**: Always read fresh balance from D1 for every player at payout time, regardless of `totalWon`:
```js
// Replace the `if (totalWon > 0)` block with:
const row = await this.env.DB.prepare(
  'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
).bind(player.userId, today).first();
if (row) {
  const session = JSON.parse(row.session_state);
  if (totalWon > 0) {
    session.balance += totalWon;
    await this.env.DB.prepare(
      'UPDATE blackjack_sessions SET session_state = ? WHERE user_id = ? AND date = ?'
    ).bind(JSON.stringify(session), player.userId, today).run();
  }
  newBalance = session.balance;
  player.balance = newBalance;
}
```

---

### [IMPORTANT] Monthly leaderboard spins column name mismatch
**File**: `functions/api/blackjack/leaderboard.js:64` / `frontend/lib/blackjack/blackjack_lobby_screen.dart:672`

The leaderboard JS merges monthly roulette stats as `spins_played` on each row:
```js
spins_played: rouletteMapMonthly[row.user_id] || 0,
```
The Flutter widget reads `row['total_spins']` for the monthly tab:
```dart
final spins = row['total_spins'] ?? 0;  // always 0
```
Monthly spins will always show as zero.

**Fix**: Change the Flutter widget to read `row['spins_played']` for both daily and monthly tabs (they use the same field name in the API response):
```dart
final spins = row['spins_played'] ?? 0;
```

---

### [IMPORTANT] Roulette-only players invisible on leaderboard
**File**: `functions/api/blackjack/leaderboard.js`

The daily and monthly leaderboard queries are anchored to `blackjack_results` / `blackjack_sessions`. A player who plays roulette but has never touched blackjack has no row in either table, so they never appear in the `UNION ALL` result set. The subsequent JS merge can only attach `spins_played` to rows that already exist — it cannot introduce new rows.

This means a roulette-only player's activity (and the balance change it causes) is invisible on the leaderboard until they play at least one hand of blackjack.

The spec note says "the profit calculation already captures roulette" because roulette writes the shared `blackjack_sessions` balance — but only if that row exists. If roulette created the session row (which `_handleJoin` does via `INSERT`), that row will appear in the `blackjack_sessions` UNION branch, so roulette-only players **do** get a session row and **should** appear. However, the `getToday()` weekend-mapping in the roulette worker must align with whatever `getToday()` the blackjack leaderboard endpoint uses, otherwise the date keys won't match.

**Verify**: Confirm that `getToday()` in `src/roulette-worker.js` and `getToday()` imported by `leaderboard.js` (from `src/db.js`) apply the same weekend-mapping logic before declaring this safe.

**Fix if divergent**: Extract `getToday` into a shared module or inline the same logic in both files.

---

### [IMPORTANT] `high` bet: 0 not excluded (spec says high = 19–36)
**File**: `src/roulette-worker.js:449–450`

```js
case 'high':
  if (winningNumber >= 19) payout = bet.amount * 2;
```
`winningNumber` ranges 0–36. `0 >= 19` is false, so zero does not pay on `high`. This is **correct** — 0 is excluded by the `>= 19` condition. ✅ Not a bug; noted here to close this checklist item.

---

### [SUGGESTION] `bet_placed` echo causes own bet to be counted twice in `_myBets`
**File**: `frontend/lib/blackjack/roulette/roulette_screen.dart:162–170`

When the server echoes `bet_placed` back to the sender, the screen adds the bet to `_myBets`. The dev notes flag this as a known open issue: "may need to only add to `_myBets` from the server echo". Currently there is no local-add before the echo — the `bet_placed` handler is the only place `_myBets` is appended. So double-counting only occurs if the server sends two `bet_placed` messages for the same bet, which it doesn't. This is safe as-is, but the devnote warning is slightly misleading.

---

### [SUGGESTION] Reconnect sends `join` before confirming widget is still mounted
**File**: `frontend/lib/blackjack/roulette/roulette_websocket.dart:31–35`

The 2-second reconnect delay fires a new `_doConnect()` which immediately sends a `join` message. If the user navigated away during those 2 seconds and `dispose()` was called (`_intentionallyClosed = true`), the reconnect is correctly suppressed. However `dispose()` only sets the flag — it doesn't cancel an already-scheduled `Future.delayed`. If `dispose()` is called after the delay fires but before `_doConnect` runs, the join message is still sent (though the channel will promptly be closed). This is the same pattern used by the chess/blackjack-mp clients so it is a pre-existing acceptable risk, not a regression.

---

## Verdict
**Requires fixes** — three Critical issues must be resolved before deploy:

1. Add `ROULETTE_TABLE` DO binding to `wrangler.toml` (Pages project). Without it, status.js crashes silently and the wheel can never be reached from the lobby.
2. Fix `result` message to include `yourNewBalance` (or read `newBalance` from the payouts array in the Flutter client). Without it, the balance display never updates after a win.
3. Fix losing-player `newBalance` in the `payouts` array (read fresh D1 balance for all players, not just winners). Without it, the result overlay shows the wrong post-round balance for losing players.

Also fix the monthly `total_spins` → `spins_played` key mismatch (Important) before the monthly leaderboard tab is meaningful.
