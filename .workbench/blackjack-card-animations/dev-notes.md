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
