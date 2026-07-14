# Dart Developer Notes — fix dealer value jump + immediate win highlight

## Files Modified
- `frontend/lib/blackjack/blackjack_screen.dart` — two targeted fixes described below

## Fix 1: Dealer value jumps during reveal animation (line ~717)

**Root cause**: `_applyState` correctly sets `_displayedDealerValue = _dealerTotal` (e.g. 22) when game ends, but the dealer's `AnimatedHand.onCardFlipped` callback then overwrites it with incrementally-computed partial values (e.g. 14 → 15 → 22) as each card flips in.

**Fix**: Wrapped the callback body in `if (_state != 'result')`. During initial deal `_state == 'playing'` so the progressive update still works for the one visible card. During stand/game-over `_state == 'result'` so the authoritative server value is preserved.

```dart
onCardFlipped: (index) {
  // Only update progressively during active play.
  // On game over, the value was already set authoritatively from server.
  if (_state != 'result') {
    setState(() {
      final visibleCards = _dealerCards
          .sublist(0, index + 1)
          .where((c) => c['rank'] != 'hidden')
          .toList();
      _displayedDealerValue = _calculateHandValue(visibleCards);
    });
  }
},
```

## Fix 2: Win highlight now appears immediately, not after 3s delay

**Root cause**: Both the dealer and player container `Border.all` conditions included `&& _showResult`, which is a 3-second delayed flag. This meant the green highlight only appeared together with the result text — losing the "hint" effect.

**Fix**: Removed `_showResult` from both border color/width conditions. The result text and action buttons remain gated on `_showResult`.

Dealer border (line ~694):
```dart
color: (_state == 'result' && _isDealerWin())  // was: && _showResult &&
```

Player border (line ~741):
```dart
color: (_state == 'result' && _isPlayerWin())  // was: && _showResult &&
```

## Packages & Docs Consulted
None — pure logic fix, no package changes.

## Analyze & Test Results
`analyze_files` on `lib/blackjack/blackjack_screen.dart` → **No errors**

## Open Issues
None.
