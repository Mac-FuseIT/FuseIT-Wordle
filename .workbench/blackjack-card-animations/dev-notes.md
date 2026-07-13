## Dart Developer Notes — AnimatedCard widget (Task 1)

### Files Created
- `frontend/lib/blackjack/widgets/animated_card.dart` — Self-contained `StatefulWidget` with `TickerProviderStateMixin` that handles slide-in + 3D Y-axis flip animation for a single blackjack card.

### Files Modified
None.

### Key Decisions

**Two separate `AnimationController`s:**  
`_slideController` (300ms) and `_flipController` (400ms) are kept separate so they can be driven sequentially with a 100ms pause in between. Trying to combine them into one controller with an `Interval` curve would have made the flip-only path (dealer hole reveal) harder to trigger independently.

**Nullable controllers:**  
Both controllers are declared nullable (`AnimationController?`). They are `null` when the widget is in skip-animation mode or when the card is hidden. This avoids creating unused `AnimationController` objects (which allocate a `Ticker`) for the common "show all cards instantly on reconnect" case.

**Hidden card → never animated on initial display:**  
When `cardData['rank'] == 'hidden'`, the widget renders the card back immediately with no controllers, matching the spec. When the card data later changes to a real rank/suit via `didUpdateWidget`, a flip-only animation fires (no slide, since the card is already in position). If `_flipController` does not yet exist at that point, it is created on demand.

**`_isHiddenCard()` check precedes `skipAnimation` in `build`:**  
Hidden cards must always show the back regardless of `skipAnimation` (you can't skip-reveal a card whose data is still hidden). The build method handles this correctly.

**`AnimatedBuilder` with `Listenable.merge`:**  
Both controllers are merged into one listenable so a single `AnimatedBuilder` drives the entire visual. When the flip controller is `null` (before `didUpdateWidget` creates it), only the slide controller is merged.

**Card face visual matches `_buildCard` in `blackjack_screen.dart`:**  
- White background, `Colors.grey.shade300` border, `BorderRadius.circular(4)`
- Red color for hearts/diamonds, black for clubs/spades
- `fontSize: 16` for rank, `fontSize: 14` for suit symbol — matches the spec

### Packages & Docs Consulted
- `dart:math` (stdlib) — for `pi` constant used in the Y-axis rotation.
- No third-party packages required.
- Existing `blackjack_screen.dart` — read to match `_buildCard` visual style exactly.
- `.workbench/blackjack-card-animations/spec.md` — used as source of truth throughout.

### Analyze & Test Results
```
analyze_files → No errors
```
No widget tests written for this task (spec does not call for them in Task 1; testing is an open item for the reviewer).

### Open Issues
- **Widget tests:** No automated tests yet. A golden/snapshot test for each animation state (pre-slide, mid-flip, revealed) would be valuable.
- **`_buildCardBack` border radius:** The spec snippet uses `BorderRadius.circular(4)` while the existing `_buildCard` in `blackjack_screen.dart` uses `BorderRadius.circular(8)`. The spec takes precedence here; `circular(4)` is used in `AnimatedCard`. The reviewer may want to align these.
- **Task 2 (`AnimatedHand`)** is not yet implemented — this file only covers Task 1.

---

## Dart Developer Notes — AnimatedHand widget (Task 2)

### Files Created
- `frontend/lib/blackjack/widgets/animated_hand.dart` — `StatefulWidget` that orchestrates a list of `AnimatedCard` widgets with staggered timing, state tracking for new-vs-revealed cards, and completion callbacks.

### Files Modified
- `frontend/lib/blackjack/widgets/animated_card.dart` — Replaced the previous version on the branch with the full implementation matching the spec (slide + 3D flip, hidden-card support, `skipAnimation` mode, `didUpdateWidget` flip-only path). No API surface changes.

### Key Decisions

**`_effectiveRevealedCount` = max(revealedCount, _previousLength):**  
Cards that were animated in a prior cycle must never be re-animated. `_previousLength` grows monotonically between rounds, so taking the max of the prop and the tracked length is the simplest way to ensure idempotency across rebuilds that don't change the list length.

**`_totalNewCards` initialised in `initState`:**  
On the very first build the widget may already have cards (e.g. initial deal on reconnect). `_totalNewCards` is set to `cards.length - revealedCount` when `animateNewCards` is true, so the very first deal is also tracked for `onAllFlipsComplete`.

**No extra timer / Future logic in `AnimatedHand`:**  
All delay logic lives inside `AnimatedCard.slideDelay`. `AnimatedHand` only computes `delay = delayBetweenCards * newCardIndex` and passes it down. This keeps `AnimatedHand` free of async state.

**`_flippedCount` is not reset in `build`:**  
Only reset in `didUpdateWidget` when the list grows. This is intentional — a re-render triggered by unrelated parent state must not reset the completion counter mid-animation.

**`onFlipComplete: null` for old/skip cards:**  
Cards rendered with `shouldSkip = true` have no `onFlipComplete` callback. This avoids `_onCardFlipped` being called for already-revealed cards and keeps `_flippedCount` accurate.

### Packages & Docs Consulted
- No third-party packages. Pure Flutter SDK.
- `.workbench/blackjack-card-animations/spec.md` — source of truth.
- `.workbench/blackjack-card-animations/task.md` — sub-task specification.

### Analyze & Test Results
```
analyze_files → No errors
```

### Open Issues
- **Task 3 & 4** (solo and multiplayer screen integration) not yet done.
- **Widget tests** for `AnimatedHand` (stagger timing, callback sequencing) would add confidence — recommended before reviewer sign-off.

## Dart Developer Notes — Integrate AnimatedHand into solo blackjack_screen.dart

### Files Created
- None

### Files Modified
- `frontend/lib/blackjack/blackjack_screen.dart` — Integrated `AnimatedHand` widget for animated card dealing

### Key Decisions

**`_isInitialLoad` flag placement:** Set to `true` in `_loadSession()` (not `initState`) because `initState` runs before any data arrives. Cleared to `false` immediately before `_applyState()` in `_placeBet()` — this ensures the very first deal animates, while page-refresh mid-hand shows cards instantly.

**Previous card count saved before `setState`:** `prevPlayerCount`/`prevDealerCount` are local variables captured before the `setState` block, then assigned to `_previousPlayerCardCount`/`_previousDealerCardCount` inside it. This avoids a race where `_playerCards` is updated before we snapshot the old length.

**Dealer `_isAnimating` off-flag:** Both dealer and player `onAllFlipsComplete` set `_isAnimating = false`. Since both callbacks fire independently, this is fine — the last one to fire wins, and both clear the flag. In practice the player hand completes first (player cards arrive before dealer draws).

**Dealer value display condition:** Changed `if (_state == 'result' || _dealerTotal > 0)` to `if (_state == 'result' || _displayedDealerValue > 0)` so the dealer value label only appears after at least one dealer card has flipped.

**`_buildCard()` retained:** The `_buildCard()` method is no longer called from `_buildCardTable()`, but it's still referenced by nothing — left in place since `AnimatedCard` internally uses the same visual logic and removing it could confuse future readers comparing the two. No lint warning generated.

**Stand / dealer reveal:** The spec requires `_previousDealerCardCount = 2` for the stand case. This is handled automatically — when `_stand()` calls `_applyState()`, the saved `prevDealerCount` is already `_dealerCards.length` (which is 2 after the initial deal: one face-up, one hidden). `AnimatedHand` receives `revealedCount: 2`, so indices 0 and 1 skip the slide animation. The hidden→real flip on index 1 is handled by `AnimatedCard.didUpdateWidget`.

### Packages & Docs Consulted
None — no new packages. All changes use existing Flutter APIs and project conventions.

### Analyze & Test Results
```
dart analyze lib/blackjack/blackjack_screen.dart
→ No errors
```

### Open Issues
- `_buildCard()` is now dead code. Can be removed in a cleanup pass or kept as visual reference for the `AnimatedCard` implementation.
- Both player and dealer `onAllFlipsComplete` independently clear `_isAnimating`. For the stand action, dealer cards animate after player finishes — consider only clearing `_isAnimating` from the dealer callback in that scenario. Current behaviour is functionally correct (buttons re-enable after player cards flip, before dealer draws, which is acceptable UX).

## Dart Developer Notes — Wave 3: Integrate AnimatedHand into multiplayer screen

### Files Created
- None (Wave 3 is purely integration work)

### Files Modified
- `frontend/lib/blackjack/blackjack_mp_screen.dart` — replaced static card rendering with AnimatedHand, added animation state fields, updated message handlers, added helper methods, disabled buttons during animation

### Key Decisions

**Animation state fields added:**
- `_displayedPlayerValues` (Map<int,int>) — per-player value shown in UI, updated only as each card flip completes
- `_displayedDealerValue` (int) — same for dealer
- `_previousCardCounts` (Map<int,int>) — snapshot of each player's card count *before* new cards arrive; passed as `revealedCount` to AnimatedHand so it knows which cards are already visible
- `_previousDealerCardCount` (int) — same for dealer
- `_isInitialState` (bool) — set true on `game_state` (reconnection/first load); causes all current cards to render instantly via `revealedCount = hand.length`
- `_isAnimating` (bool) — set true when cards_dealt / card_drawn / dealer_turn arrives; cleared by `onAllFlipsComplete`

**Snapshot-before-update pattern:**
In `cards_dealt`, `card_drawn`, and `dealer_turn` handlers, previous card counts are snapshotted *before* the state update inside the same `setState()` call. This is safe because `_previousCardCounts` is read only by the build method (after setState completes), never inside the handler.

**`_isInitialState` on `game_state`:**
Every `game_state` message (which arrives on reconnect or initial join) sets `_isInitialState = true` and populates `_displayedPlayerValues` / `_displayedDealerValue` directly from server values. This ensures cards appear instantly without animation on reconnect, matching the spec requirement.

**`_isInitialState` reset:**
Set to `false` inside the `cards_dealt` handler. This means the very first deal after joining animates normally; only reconnection mid-round skips animation.

**Dead code:**
`_buildCard()` and `_buildSmallCard()` are no longer called from any build path but have been left in place. Safe to remove in a future cleanup commit.

**`_calculateHandValue` empty-rank guard:**
The filter `c['rank'] != 'hidden'` in the `onCardFlipped` callbacks already strips hidden cards before calling the helper, but the helper itself also guards against empty strings to be defensive.

### Packages & Docs Consulted
- No new packages added.
- No Context7 lookups needed — all APIs are standard Flutter/Dart.

### Analyze & Test Results
```
No errors (dart analyze frontend/lib/blackjack/blackjack_mp_screen.dart)
No errors (dart analyze frontend/lib/blackjack/)
```

### Open Issues
- `_buildCard()` and `_buildSmallCard()` are dead code — remove in a follow-up cleanup.
- `_isAnimating` is only cleared by `onAllFlipsComplete` of the *local player's* seat (or the dealer area). If the local player has no cards (spectator mode / edge case), `_isAnimating` might never clear. Low risk for the current game design (all seated players are dealt cards), but worth noting.
