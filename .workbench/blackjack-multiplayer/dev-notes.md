## Developer Notes — Critical bug fixes in blackjack-mp-worker.js

### Files Modified
- `src/blackjack-mp-worker.js` — three targeted bug fixes (see below)

### Key Decisions

**Fix 1 — `getToday()` weekend mapping**
The original `getToday()` returned a raw UTC date with no weekend adjustment. `src/db.js` maps Sat→Fri and Sun→Fri so all solo sessions share the same Friday row. Without the same mapping in the DO, a player betting on Saturday or Sunday would hit a different `blackjack_sessions` row than their solo game, breaking balance continuity. Fixed by applying the identical offset logic.

**Fix 2 — `_handleLeave` impossible game-over condition**
The original condition was:
```js
if (state.players.filter(p => !p.pendingLeave).length === 0 && state.players.length === 0)
```
The `&&` makes this impossible mid-round: when `pendingLeave` is used, players remain in `state.players` (length > 0), so the second clause always blocks. The game would never be marked finished or sockets closed when the last player leaves during a round. Dropped the second clause.

**Fix 3 — D1 `player_count` over-counting pending-leave players**
`state.players.length` includes players marked `pendingLeave: true` who are effectively gone. Using `activeCount` (filtering them out) keeps the D1 lobby count accurate so new joiners see the real available seat count.

### Library Docs Consulted (Context7)
None — no third-party library touched. Pure JS logic fixes.

### Build & Test Results
```
node --input-type=module --check < src/blackjack-mp-worker.js
exit: 0  (no syntax errors)
```

### Open Issues
None. All three fixes are isolated and non-breaking.

---

## Dart Developer Notes — Fix 6 critical/important WebSocket handler bugs in blackjack_mp_screen.dart

### Files Modified
- `frontend/lib/blackjack/blackjack_mp_screen.dart` — all 6 bug fixes applied

### Changes Made

**Fix 1 — `dealer_turn` reads wrong fields (Critical)**
Old code checked `data['dealer']` wrapper object or `data['hand']`/`data['value']`.
Server actually sends `finalHand` and `finalValue` at the top level (with no `dealer` wrapper).
Fixed to: `data['finalHand'] ?? data['hand'] ?? data['cards']` and `data['finalValue'] ?? data['value']`.
Also ensures proper deep copy via `Map<String, dynamic>.from`.

**Fix 2 — `round_result` uses wrong balance key (Critical)**
Server sends `result['newBalance']`; old code read `result['balance']` → balance never updated.
Fixed all occurrences. Also added dealer hand/value update from `data['dealerHand']`/`data['dealerValue']`
so dealer is fully visible on result screen.

**Fix 3 — `cards_dealt` replaces player list (Critical)**
Old code: `_players = List.from(dealtPlayers)` wiped out non-betting players.
Fixed to iterate `dealtPlayers` and merge `hand`, `value`, `status` into matching existing players by `userId`.
Players who didn't bet remain in the list.

**Fix 4 — `player_doubled` reads wrong bet key (Critical)**
Server sends `data['newBet']`; old code read `data['bet']` → bet amount never doubled in UI.
Fixed to `data['newBet'] ?? data['bet'] ?? updated['bet']` (fallback chain for safety).
Also added `status` update: sets 'bust' if value > 21, else 'stood' (double always ends turn).

**Fix 5 — `player_joined` incomplete player object (Important)**
Old code: shallow-copied whatever the server sent, which could be missing fields like `hand`, `value`,
`status`, `disconnected`. Any widget code reading those fields would null-crash or show wrong state.
Fixed to build explicit full skeleton with all required fields.

**Fix 6 — `canDouble` server signal ignored (Important)**
Old code derived `canDouble` from `hand.length == 2` locally — ignores server's authoritative check
(balance, split state, etc.). Added `bool _canDouble = false;` state field.
`turn_start` handler now reads `data['canDouble'] ?? false` from server.
`_buildPlayActions` uses `_canDouble && _isMyTurn()` instead of local hand-length check.

### Key Decisions
- All fixes are exact as specified — no scope creep.
- Fix 4 keeps a fallback chain `newBet ?? bet ?? existing` for resilience against older server versions.
- Fix 3 only updates players found by `userId` — new players from dealt list who aren't in `_players`
  are silently skipped (they should have arrived via `player_joined` earlier).

### Packages & Docs Consulted
None — pure Dart/Flutter logic, no new packages.

### Analyze & Test Results
`analyze_files` on `blackjack_mp_screen.dart` → **No errors**

### Open Issues
None.
