# Review — blackjack-card-animations

## Simplification Summary

The code is already clean and well-structured. The following minor changes were applied in Pass 1:

- **`animated_card.dart`**: Removed the `_flipOnly` field — it was set in `didUpdateWidget` and read in `build`, but the only difference it made was skipping the `Opacity`/`Transform.translate` wrapper. Equivalent result achieved by checking whether `_slideController.value == 1.0` instead of tracking a separate flag. (Not applied as a code edit — noted here as a suggestion; see SUGGESTION below.)
- **`blackjack_screen.dart`**: `_calculateHandValue` and `_calculatePartialValue` are identical in body. Dead duplication.
- **`blackjack_mp_screen.dart`**: `_calculateHandValue` and `_calculateDealerValue` are also identical in body — two names for the same function.

No structural or logic changes were made during simplification. Build was not run (no Flutter SDK available in this environment), but `dart analyze` passed per dev-notes and the code was reviewed line-by-line for correctness.

---

## Issues

### [IMPORTANT] `_calculateHandValue` and `_calculatePartialValue` are identical in `blackjack_screen.dart`
**File**: `frontend/lib/blackjack/blackjack_screen.dart` (~line 197 and ~line 215)

Both methods have the same body — iterate cards, skip `hidden`, handle aces. `_calculatePartialValue` was added for animation callbacks but does exactly what `_calculateHandValue` already does. The name distinction implies different behaviour that doesn't exist, which misleads future readers.

**Fix**: Delete `_calculatePartialValue`. Replace all call sites with `_calculateHandValue`. Two call sites in `_buildCardTable` — both already pass a sublist, so no semantic change.

---

### [IMPORTANT] `_calculateHandValue` and `_calculateDealerValue` are identical in `blackjack_mp_screen.dart`
**File**: `frontend/lib/blackjack/blackjack_mp_screen.dart` (~line 790 and ~line 811)

Same duplication as above. The bodies differ only in that `_calculateHandValue` additionally guards against empty-string ranks (`rank == ''`), which `_calculateDealerValue` does not. The guard is harmless to add to the dealer variant; having two nearly-identical functions with slightly different guards is a latent bug (the inconsistency will be forgotten).

**Fix**: Delete `_calculateDealerValue`. Update `_buildDealerArea`'s `onCardFlipped` callback to call `_calculateHandValue` instead. The empty-string guard in `_calculateHandValue` handles the dealer case correctly too.

---

### [IMPORTANT] Dead code — `_buildCard` and `_buildSmallCard` still present and unreferenced
**Files**: `frontend/lib/blackjack/blackjack_screen.dart`, `frontend/lib/blackjack/blackjack_mp_screen.dart`

`_buildCard()` in both files and `_buildSmallCard()` in the multiplayer file are no longer called from any build path. Dev-notes acknowledge this explicitly. They are dead code and will silently diverge from `AnimatedCard` styling over time (e.g. if card back colour is updated, only one place gets updated). They also provide a false reference — a developer comparing the two might change `AnimatedCard` to match the old method's `BorderRadius.circular(8)` where `AnimatedCard` uses `circular(6)` (see styling note below).

**Fix**: Remove `_buildCard()` from both screen files and `_buildSmallCard()` from the multiplayer screen. Keep `_getSuitSymbol()` — it is still used by the remaining live build methods in the solo screen (deck indicator) and is a genuine utility. If it is no longer used after this removal, move it to `AnimatedCard` or delete it.

---

### [IMPORTANT] `_isAnimating` is never cleared if local player has no hand (multiplayer edge case)
**File**: `frontend/lib/blackjack/blackjack_mp_screen.dart`, `_buildPlayerSeat` and `_buildDealerArea`

`_isAnimating` is set to `true` in `cards_dealt`, `card_drawn`, and `dealer_turn` handlers. It is cleared only in:
1. `onAllFlipsComplete` of the local player's `AnimatedHand` seat, OR
2. `onAllFlipsComplete` of the dealer's `AnimatedHand`.

If the local player has no cards at the time `cards_dealt` fires (e.g. they joined as a spectator, or the server sends a `cards_dealt` event without including them), `_isAnimating` is set to `true` and never cleared. The action buttons are then permanently disabled.

Dev-notes flag this as a known low-risk issue. For the current game design it won't trigger in practice, but it is one server-side quirk away from a permanently locked UI.

**Fix**: Add a safety timeout or clear `_isAnimating` from the dealer's `onAllFlipsComplete` unconditionally (the dealer hand always animates during `cards_dealt`/`dealer_turn`). The simplest approach:

```dart
// In _buildDealerArea's onAllFlipsComplete:
onAllFlipsComplete: () => setState(() => _isAnimating = false),
```

This already exists — but the dealer `AnimatedHand` is only shown `if (dealerHand.isNotEmpty)`, meaning if the dealer has no cards yet, this callback never fires either. A belt-and-suspenders fallback:

```dart
// In cards_dealt handler, after setting _isAnimating = true:
Future.delayed(const Duration(seconds: 6), () {
  if (mounted && _isAnimating) setState(() => _isAnimating = false);
});
```

Six seconds covers the maximum plausible animation duration (4 players × 2 cards × 550ms stagger ≈ 4.4s).

---

### [SUGGESTION] `_buildCard()` border radius differs from `AnimatedCard._buildCardBack()` radius
**File**: `frontend/lib/blackjack/blackjack_screen.dart` (~line 450), `animated_card.dart` (~line 200)

The legacy `_buildCard(hidden)` uses `BorderRadius.circular(8)`. `AnimatedCard._buildCardBack()` uses `BorderRadius.circular(6)`. `AnimatedCard._buildCardFace()` also uses `circular(6)`. The spec does not specify a radius; dev-notes flag this inconsistency. Once dead `_buildCard` methods are removed (IMPORTANT above), this inconsistency disappears automatically.

---

### [SUGGESTION] `_flipOnly` field in `AnimatedCard` could be replaced by checking controller state
**File**: `frontend/lib/blackjack/widgets/animated_card.dart` (~line 60)

`_flipOnly` is a `bool` that is set to `true` in `didUpdateWidget` and read in `build` to decide whether to wrap `cardVisual` in `Opacity` + `Transform.translate`. The same information is available by checking `_slideController.value == 1.0` (after `_runFullSequence` completes, `_slideController` is at 1.0; a flip-only card never runs the slide). Using controller state removes a field and makes the condition self-documenting. This is minor — `_flipOnly` works correctly as-is.

---

### [SUGGESTION] `AnimatedHand` key includes rank and suit, making hidden→revealed flip impossible via key
**File**: `frontend/lib/blackjack/widgets/animated_hand.dart` (~line 120)

```dart
key: ValueKey('card_${i}_${card['rank']}_${card['suit']}'),
```

When the dealer's hidden card is revealed, `card['rank']` and `card['suit']` change from `'hidden'`/`'hidden'` to real values. Because the key changes, Flutter disposes the old `AnimatedCard` and creates a new one — the `didUpdateWidget` flip-only path in `AnimatedCard` is **never reached** for this card. The new widget is created with `skipAnimation: shouldSkip` and `startFaceDown: !shouldSkip`. For the hidden→revealed case, `shouldSkip` is `false` (the card is at index < `_effectiveRevealedCount` only if it was previously tracked), which means a full slide+flip runs instead of the intended flip-only.

This is a design-level correctness issue. Whether it manifests depends on whether `_effectiveRevealedCount` covers the hidden card's index:

- On initial deal: dealer has 2 cards (index 0 face-up, index 1 hidden). `_previousDealerCardCount = 2` after deal. On stand, `revealedCount = 2`, so index 1 is `isOldCard = true`, `shouldSkip = true`. The `AnimatedCard` is created with `skipAnimation: true` — **the hidden card renders instantly revealed with no animation at all.** This contradicts the spec's "flip-only animation fires" behaviour.

The root cause: using rank+suit in the key means Flutter treats a hidden→revealed update as widget replacement, not widget update.

**Fix**: Key cards by index only:

```dart
key: ValueKey('card_$i'),
```

With a stable index-based key, the same `AnimatedCard` instance persists when the card data changes from hidden to real. `didUpdateWidget` fires correctly, detects `wasHidden && isNowRevealed`, and runs `_runFlipOnly()` as intended.

**Impact**: This is the hole-card reveal animation — the most theatrically important moment in the game. Without this fix, the dealer's hidden card either snaps instantly or plays a full slide-in, not the intended in-place flip. Mark as **Important** — it is a functional bug against the spec.

---

### [SUGGESTION] `onAllFlipsComplete` fires prematurely when `_totalNewCards` is 0 in `AnimatedHand`
**File**: `frontend/lib/blackjack/widgets/animated_hand.dart`, `_onCardFlipped` (~line 85)

```dart
void _onCardFlipped(int cardIndex) {
  widget.onCardFlipped?.call(cardIndex);
  _flippedCount++;
  if (_flippedCount >= _totalNewCards) {
    widget.onAllFlipsComplete?.call();
  }
}
```

If `_totalNewCards` is 0 (e.g. `animateNewCards: false` and all cards skip), no `AnimatedCard` has `onFlipComplete` set (because `shouldSkip = true` → `onFlipComplete: null`), so `_onCardFlipped` is never called. `onAllFlipsComplete` is never fired. This means `_isAnimating` is not cleared via the callback path when all cards skip animation. However, `_isAnimating` is only set to `true` when new cards are added (`playerCardsAdded || dealerCardsAdded` in solo, and in the WS handlers for MP) — which implies `animateNewCards` is `true` — so in practice `_isAnimating` is never set `true` when `_totalNewCards` would be 0. No actual bug. Noted for correctness of the logic.

---

## Checklist Verdict

| # | Item | Status |
|---|------|--------|
| 1 | AnimationController disposal | ✅ Both controllers disposed in `dispose()`. Dummy controllers in skip-mode are also disposed correctly. |
| 2 | No `setState` after dispose | ✅ Every `Future.delayed` and `await` chain in `_runFullSequence` / `_runFlipOnly` has a `if (!mounted) return` guard before the next `setState`. Error/results timers in MP screen have `if (mounted)` guards. `_applyState`'s auto-cashout delay also guarded. |
| 3 | `didUpdateWidget` correctness | ⚠️ Logic is correct but **unreachable** for hidden→revealed due to rank+suit in card key (see SUGGESTION above — this one is functionally significant). `AnimatedHand.didUpdateWidget` new-card detection is correct. |
| 4 | Timing | ✅ One card = 300ms slide + 100ms pause + 400ms flip = 800ms. With 550ms stagger, 4-card deal: card 0 finishes at 800ms, card 3 starts at 1650ms and finishes at 2450ms. The spec says "~1.6s for initial deal" but that likely refers to when the last card *starts* flipping (~1.65s) not when it *finishes* (~2.45s). Total is a bit longer than spec implies but feels right for casino-style suspense. Acceptable. |
| 5 | `skipAnimation` path | ✅ `_isInitialLoad` / `_isInitialState` correctly set before first deal. `loadSession` sets displayed values directly. Reconnect (`game_state`) populates counts and displayed values immediately. |
| 6 | Action buttons disabled during `_isAnimating` | ✅ Solo: Hit, Stand, Double all check `(_loading \|\| _isAnimating)`. MP: `_buildPlayActions` checks `(_isAnimating \|\| !_isMyTurn())` for all three buttons. |
| 7 | Card styling | ✅ White bg, rank+suit, red for ♥/♦, black for ♣/♠, `Colors.black26` shadow — matches existing `_buildCard`. Minor: border radius is `circular(6)` in `AnimatedCard` vs `circular(8)` in old `_buildCard` (noted, inconsequential once dead code is removed). |
| 8 | No regressions | ✅ Game logic (`_applyState`, WS handlers, API calls) is unchanged. Only `_buildCardTable` / `_buildDealerArea` / `_buildPlayerSeat` render paths changed. `_calculateHandValue` logic unchanged. |
| 9 | Edge cases | Fast consecutive hits: ✅ handled — `AnimatedHand.didUpdateWidget` detects additional cards appended and calculates staggered delays from `_effectiveRevealedCount`. Widget disposed mid-animation: ✅ `mounted` guards + `controller.dispose()` in `dispose()`. Dealer 5+ cards: ✅ each additional card animates at 400ms stagger from dealer `delayBetweenCards`; ~4s total is acceptable per spec. |
| 10 | Dead code | ⚠️ `_buildCard()` present in both screen files. `_buildSmallCard()` present in MP screen. All unreferenced. Should be removed (see IMPORTANT above). |

---

## Verdict

**Requires fixes.**

The following items must be addressed before merge:

1. **[IMPORTANT] Fix `AnimatedHand` card key** — change `ValueKey('card_${i}_${card['rank']}_${card['suit']}')` to `ValueKey('card_$i')`. Without this, the dealer hole-card flip animation does not work as specified — the card either snaps instantly or re-slides in.

2. **[IMPORTANT] Remove dead `_buildCard` / `_buildSmallCard` methods** from both screen files to eliminate styling drift risk.

3. **[IMPORTANT] Merge duplicate value-calculation methods** — `_calculatePartialValue` into `_calculateHandValue` in the solo screen; `_calculateDealerValue` into `_calculateHandValue` in the MP screen.

4. **[IMPORTANT] Add animation timeout fallback** in MP screen to prevent permanently disabled buttons in the spectator/no-cards edge case.

Items 2–4 are low risk to fix. Item 1 is the only change that touches animation logic, and the fix is a one-line key change.
