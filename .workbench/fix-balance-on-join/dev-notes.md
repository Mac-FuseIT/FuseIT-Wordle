## Developer Notes — Fix Balance: $0 on multiplayer join

### Files Modified
- `src/blackjack-mp-worker.js` — Inserted D1 balance fetch in `_handleJoin()` after `state.players.push(...)` and before `ws.serializeAttachment(...)`. Removed stale comment `// fetched from D1 on first bet` from the `balance: 0` initializer line.

### Key Decisions
- Inserted the fetch block between `push` and `serializeAttachment` exactly as specified so the player object carries the real balance before the `game_state` snapshot is sent to the client.
- Used `state.players[state.players.length - 1]` (last element) rather than a local reference to avoid any closure issues with the async block.
- Kept the `balance: 0` initializer in the push so the object shape is always complete even if the try block is entered and throws before assignment.
- Fall-through catch defaults to 100 (matching `defaultSession()` logic) so players are never stuck at $0 even on a D1 failure.

### Library Docs Consulted (Context7)
None — no third-party libraries touched. Only Cloudflare D1 bindings already present in the codebase.

### Build & Test Results
```
$ node --input-type=module --check < src/blackjack-mp-worker.js
# exit 0, no output — syntax clean
```

### Open Issues
None.

---

## Developer Notes — Three backend fixes (deckRemaining, duplicate game prevention, uncashout endpoint)

### Files Created
- `functions/api/blackjack/uncashout.js` — POST endpoint that lets a player "cash back in" by deleting their cashout record and returning current session balance

### Files Modified
- `src/blackjack-mp-worker.js` — Added `deckRemaining: state.deck.length` to the object returned by `getGameStateFor()`, after the `dealer` field
- `functions/api/blackjack-mp/create.js` — Added duplicate game check before `crypto.randomUUID()`: queries for any active (non-finished) game owned by this creator and returns it instead of creating a new one

### Key Decisions
- `deckRemaining` placed after `dealer` field as specified — keeps object shape consistent with the order fields are set
- Duplicate check uses `status != 'finished'` so any game in `waiting`, `playing`, etc. is considered active
- `uncashout.js` returns `cashedOut: false` alongside the balance so the frontend can update state in one response

### Library Docs Consulted (Context7)
None — no new third-party libraries introduced. Uses existing D1 bindings and helper imports already present in the codebase.

### Build & Test Results
```
$ node --input-type=module --check < src/blackjack-mp-worker.js
# exit 0, no output — syntax clean
```

### Open Issues
None.
## Dart Developer Notes — Deck count display, cash back in, duplicate game handling

### Files Modified
- `frontend/lib/blackjack/blackjack_mp_screen.dart` — Added `_deckRemaining` state variable; updated from `game_state` (authoritative) and decremented locally in `cards_dealt`, `card_drawn`, `player_doubled`, `dealer_turn`. Added deck count label ("Deck: N") in the dealer area Row using a Spacer to push it to the right.
- `frontend/lib/blackjack/blackjack_lobby_screen.dart` — Added `_uncashout()` method (POST `/api/blackjack/uncashout`, then `_load()`). Added "Cash Back In" outlined button at the bottom of the cashed-out status card, styled with `widget.theme.present` colour.

### Key Decisions
- Deck display: placed in the dealer area header Row using a `Spacer()` so "Dealer [value]" stays centred-ish and "Deck: N" is right-aligned — avoids a separate row and keeps the card area uncluttered.
- Deck decrement logic: `cards_dealt` subtracts `players * 2 + 2`; `card_drawn` and `player_doubled` subtract 1; `dealer_turn` subtracts `dealerCardCount - 2` (extra draws beyond the initial 2). Floor-clamped to 0.
- Fix 3 (duplicate game): confirmed `_createMpGame` already reads `data['gameId']` unconditionally — no code change required.

### Packages & Docs Consulted
None — no new packages or external docs needed.

### Analyze & Test Results
`analyze_files` on both files: **No errors**

### Open Issues
- The server may not broadcast `deckRemaining` in `game_state` yet (backend work in separate task). Until it does, the deck counter will show 52 at start and decrement locally — which is correct behaviour.
- If the server reshuffles mid-session, a `game_state` broadcast with `deckRemaining` will re-sync the display automatically.
