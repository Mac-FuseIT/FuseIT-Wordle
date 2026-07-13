# Blackjack Card Animations — Design

## Overview

Add smooth card animations to the Stack.IT blackjack game across both solo (`blackjack_screen.dart`) and multiplayer (`blackjack_mp_screen.dart`) screens. Cards slide in face-down and flip to reveal, with hand values updating only after each flip completes. This creates suspense and a polished casino feel.

## Goals & Non-Goals

**Goals:**
- Animate card dealing (initial deal, hit, dealer reveal) with slide-in + 3D flip
- Delay hand value display until each card's flip animation completes
- Reusable widget that works in both solo and multiplayer contexts
- Staggered timing for multi-card sequences (initial deal, dealer draw)
- Keep animations snappy — no sluggish waiting

**Non-Goals:**
- Card shuffle animations (existing shuffle indicator is sufficient)
- Chip/bet animations
- Sound effects
- Card removal animations (hands clear instantly between rounds)
- Animating the entire result banner

---

## Design

### Architecture

```
frontend/lib/blackjack/
├── widgets/
│   ├── animated_card.dart          # AnimatedCard widget (slide + flip)
│   └── animated_hand.dart          # AnimatedHand — orchestrates a sequence of AnimatedCards
├── blackjack_screen.dart           # Solo — uses AnimatedHand
├── blackjack_mp_screen.dart        # Multiplayer — uses AnimatedHand
└── ...
```

### AnimatedCard Widget

A self-contained `StatefulWidget` that manages its own `AnimationController`. It renders either the card back (face-down) or the card face (rank + suit), with a 3D Y-axis rotation to transition between them.

```dart
class AnimatedCard extends StatefulWidget {
  final Map<String, dynamic> cardData; // {rank, suit}
  final bool startFaceDown;            // true = animate in face-down, then flip
  final bool skipAnimation;            // true = show face immediately (reconnection)
  final Duration slideDelay;           // delay before this card starts sliding in
  final VoidCallback? onFlipComplete;  // called when flip finishes (for value update)
  final double width;
  final double height;
  
  const AnimatedCard({...});
}
```

**Animation sequence for a single card:**
1. Card starts off-screen (translated left or above) and face-down
2. Slide-in: `Transform.translate` animates from offset to zero (300ms, `Curves.easeOut`)
3. Pause: 100ms idle
4. Flip: Y-axis rotation from 0 → π (400ms, `Curves.easeInOut`). At the halfway point (π/2), swap the rendered child from card-back to card-face.
5. Fire `onFlipComplete` callback

**3D Flip implementation:**
```dart
Transform(
  alignment: Alignment.center,
  transform: Matrix4.identity()
    ..setEntry(3, 2, 0.001) // perspective
    ..rotateY(_flipAnimation.value),
  child: _flipAnimation.value < pi / 2
      ? _buildCardBack()
      : Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..rotateY(pi), // counter-rotate so face isn't mirrored
          child: _buildCardFace(),
        ),
)
```

### AnimatedHand Widget

Orchestrates a list of cards, managing staggered delays and value callbacks.

```dart
class AnimatedHand extends StatefulWidget {
  final List<Map<String, dynamic>> cards;
  final int revealedCount;             // how many cards to show revealed (no animation)
  final bool animateNewCards;          // false = show all instantly (reconnection mode)
  final Duration delayBetweenCards;    // stagger timing
  final ValueChanged<int>? onValueUpdate; // fires with new cumulative value after each flip
  final double cardWidth;
  final double cardHeight;
  
  const AnimatedHand({...});
}
```

**How it works:**
- Maintains an internal `_animatedCardCount` — the number of cards whose animations have been triggered
- When `cards.length` increases (new card added to state), the new card(s) get a `slideDelay` based on their index relative to `_animatedCardCount`
- Cards at index < `revealedCount` render with `skipAnimation: true`
- Each card's `onFlipComplete` increments a counter; when that counter matches the card's index, `onValueUpdate` fires with the partial hand value up to that card

### State Management — Delayed Value Display

The key insight: **cards are added to the state list immediately** (from API response or WebSocket message), but the **displayed value** is managed separately.

```
State:
  _playerCards: [card1, card2, card3]     ← full truth from server
  _displayedValue: 15                      ← only includes cards whose flip completed
```

Flow:
1. Server says player has cards [7♠, 8♥] with value 15
2. `_playerCards` is set to the full list immediately
3. `_displayedValue` starts at 0
4. Card 1 flip completes → `onValueUpdate(7)` → `_displayedValue = 7`
5. Card 2 flip completes → `onValueUpdate(15)` → `_displayedValue = 15`

For the **dealer's hole card reveal**: The card already exists in the list as `{rank: 'hidden', suit: 'hidden'}`. When the server sends the reveal, the card data is updated in-place. The `AnimatedHand` detects that a previously-hidden card now has real data and triggers a flip animation (no slide — card is already positioned).

### Integration: Solo Screen (`blackjack_screen.dart`)

**Current flow:** `_applyState()` sets `_playerCards`, `_dealerCards`, `_playerTotal`, `_dealerTotal` all at once from API response.

**New flow:**
1. `_applyState()` still sets `_playerCards` and `_dealerCards` immediately
2. Add `_displayedPlayerValue` and `_displayedDealerValue` state fields
3. Replace direct value display with `_displayedPlayerValue` / `_displayedDealerValue`
4. Replace `_buildCard()` calls in `_buildCardTable()` with `AnimatedHand` widget
5. Add `_isInitialLoad` flag — set true on `_loadSession()`, false after first deal. Initial load shows cards without animation (player may be refreshing mid-hand).

```dart
// In _buildCardTable(), player's hand:
AnimatedHand(
  cards: _playerCards,
  animateNewCards: !_isInitialLoad,
  revealedCount: _isInitialLoad ? _playerCards.length : _previousPlayerCardCount,
  delayBetweenCards: const Duration(milliseconds: 550),
  onValueUpdate: (value) => setState(() => _displayedPlayerValue = value),
  cardWidth: 52,
  cardHeight: 72,
)
```

**Tracking "new" vs "old" cards:**
- Store `_previousPlayerCardCount` before applying new state
- Cards at index < `_previousPlayerCardCount` already have been revealed
- Cards at index >= `_previousPlayerCardCount` are new and should animate
- After all animations complete, update `_previousPlayerCardCount`

**Dealer reveal (stand action):**
- API returns full dealer hand with all cards face-up
- Detect: dealer's first card was previously `hidden` → trigger flip-only animation on it
- Subsequent dealer cards (index >= 2) → slide + flip with faster timing

### Integration: Multiplayer Screen (`blackjack_mp_screen.dart`)

Same pattern but with WebSocket events:

- `cards_dealt` → triggers initial deal animation for all players
- `card_drawn` → triggers single card animation for the relevant player
- `dealer_turn` → triggers dealer reveal sequence

**Other players' cards:** Animate for all players. The multiplayer screen uses smaller cards (`_buildSmallCard`, 32×44). The `AnimatedCard` widget accepts `width`/`height` props to handle both sizes.

**My player seat** uses the same `AnimatedHand` with value callback. **Other player seats** also use `AnimatedHand` but the value callback updates that player's displayed value in the `_players` list.

### Timing Constants

```dart
class CardAnimationTiming {
  static const slideDuration = Duration(milliseconds: 300);
  static const pauseBeforeFlip = Duration(milliseconds: 100);
  static const flipDuration = Duration(milliseconds: 400);
  static const delayBetweenCards = Duration(milliseconds: 550);
  static const dealerDrawDelay = Duration(milliseconds: 400);
  
  // Total time for one card: 300 + 100 + 400 = 800ms
  // But next card starts after 550ms (overlapping slightly)
}
```

### Disabling Actions During Animation

While the initial deal animation plays, the Hit/Stand/Double buttons should be disabled. Add an `_isAnimating` flag:
- Set `true` when a new deal/hit starts animating
- Set `false` when the last card's `onFlipComplete` fires
- Buttons check `_isAnimating` before allowing taps

This prevents the player from hitting before the deal animation finishes (which would cause weird visual ordering).

---

## Design Decisions

### 1. Reusable `AnimatedCard` widget — YES

**Decision:** Extract into `frontend/lib/blackjack/widgets/animated_card.dart`.

**Rationale:** Both screens render cards identically (same visual, same dimensions). A shared widget avoids duplicating ~80 lines of animation code. The widget is self-contained with its own `AnimationController`, so it doesn't pollute the parent screen's state.

### 2. Animation orchestration via `AnimatedHand` widget

**Decision:** Use a stateful `AnimatedHand` widget that internally manages stagger timing, NOT Timer-based logic in the screen.

**Rationale:** 
- Timers are fragile (must be cancelled on dispose, don't compose well)
- `AnimatedHand` can use `Future.delayed` chains or a single `AnimationController` with interval-based triggers
- The widget naturally handles the "cards added to list → animate new ones" pattern by comparing `oldWidget.cards.length` in `didUpdateWidget`
- Keeps screen files clean — they just pass cards and get value callbacks

### 3. State interaction — cards in state immediately, animation is visual-only

**Decision:** The logical state (`_playerCards`, `_dealerCards`) reflects the server truth immediately. Animation is purely a visual layer. The `_displayedValue` is a separate UI-only state field.

**Rationale:**
- Simplest mental model: state = truth, animation = presentation
- No risk of state desync — if animation is interrupted (widget disposed), state is still correct
- Reconnection/refresh just sets `skipAnimation: true` and shows everything instantly
- Server responses don't need to be queued or delayed

### 4. Multiplayer — animate ALL players' cards

**Decision:** Animate other players' cards too, not just your own.

**Rationale:**
- Creates a cohesive "table" feel where you see everyone being dealt
- Small cards (32×44) animate quickly and don't obstruct
- Other players' value labels also delay-update, matching the suspense
- Since WebSocket events arrive for all players anyway, no extra complexity

### 5. Slide direction

**Decision:** Cards slide in from the LEFT (toward right into position) for a horizontal "dealing from deck" feel.

**Rationale:** A top-down slide would conflict with the vertical scroll layout. Left-to-right matches the western reading direction and the feeling of cards being pushed across the table.

---

## Tasks

1. **Create `AnimatedCard` widget** — Implement slide-in + 3D flip with configurable timing, `onFlipComplete` callback, `skipAnimation` mode. — M

2. **Create `AnimatedHand` widget** — Orchestrator that manages a list of `AnimatedCard` widgets, handles staggered delays, tracks which cards are new vs already revealed, fires `onValueUpdate` after each flip. — M

3. **Integrate into solo screen** — Replace `_buildCard` usage in `_buildCardTable()` with `AnimatedHand`. Add `_displayedPlayerValue`, `_displayedDealerValue`, `_previousPlayerCardCount`, `_isInitialLoad`, `_isAnimating` state fields. Wire up value callbacks and action-button disabling. — L

4. **Integrate into multiplayer screen** — Replace card rendering in `_buildDealerArea()` and `_buildPlayerSeat()` with `AnimatedHand`. Add per-player displayed value tracking. Handle `cards_dealt`, `card_drawn`, `dealer_turn` WebSocket events to trigger animations correctly. — L

5. **Handle dealer reveal animation** — Detect when a `hidden` card becomes revealed. Trigger flip-only (no slide) for the hole card. Then slide+flip for any additional dealer draws with faster timing. — S

6. **Handle edge cases** — Implement `skipAnimation` for page refresh / reconnection mid-hand. Ensure fast consecutive hits don't break sequencing (queue new cards behind in-progress animations). Handle widget disposal during animation gracefully. — M

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Page refresh mid-hand | `_isInitialLoad = true` → all existing cards render instantly with `skipAnimation` |
| Multiplayer reconnection | `game_state` event provides full hand → render all cards instantly, no animation |
| Fast double-tap Hit | Second hit's API call may return before first animation finishes. Queue the new card — it animates after the first card's flip completes. `AnimatedHand` handles this naturally via staggered delay from the last pending card. |
| Instant bust on hit | Card animates in, flips, THEN bust status/result appears. Use `onFlipComplete` of the last card to trigger result display. |
| Blackjack on deal | Both cards animate normally. After second card flips, blackjack result shows. Delay result banner by total animation time. |
| Widget disposed mid-animation | `AnimationController.dispose()` in widget's `dispose()`. No crashes — standard Flutter pattern. |
| Dealer draws 5+ cards | Each card animates with `dealerDrawDelay` (400ms between). Total ~4s for 5 cards is acceptable. |
| Multiplayer: player disconnects mid-animation | Animation continues to completion visually. No functional impact. |

---

## Open Questions

None — all design decisions resolved above. Ready for implementation.
