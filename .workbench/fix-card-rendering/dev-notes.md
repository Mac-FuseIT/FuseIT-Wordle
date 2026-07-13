## Dart Developer Notes — Fix card face rendering in AnimatedCard

### Files Modified
- `frontend/lib/blackjack/widgets/animated_card.dart` — replaced `_buildCardFace()` and added `_getSuitSymbol()` helper

### What Changed and Why

**Root cause:** The card data format uses full English words for suits
(`'hearts'`, `'diamonds'`, `'clubs'`, `'spades'`), but `_buildCardFace()` was:
1. Comparing `suit` against unicode symbols (`♥`, `♦`) for the red-colour check → always `false`, so all cards rendered black.
2. Displaying the raw `suit` string in the `Text` widget → cards showed text like "5 spades" instead of "5 ♠".

**Fix applied:**
- Added `_getSuitSymbol(String suit)` that maps each suit word to its unicode character.
- Updated `isRed` to compare against `'hearts'` and `'diamonds'`.
- `_buildCardFace()` now passes `suitSymbol` to the suit `Text` widget.
- Border changed from `Colors.black12` to `Colors.grey.shade300` and font sizes
  from width-relative (`widget.width * 0.35`) to fixed (`16`/`14`) to align with
  the reference rendering in `blackjack_screen.dart`.

### Key Decisions
- Kept font sizes as fixed `16`/`14` (matching the task spec) rather than restoring
  the width-relative values, since the spec explicitly provides these values and they
  align with the reference implementation.

### Packages & Docs Consulted
None — pure Dart/Flutter core APIs, no third-party packages involved.

### Analyze & Test Results
`analyze_files` on `animated_card.dart` → **No errors**

### Open Issues
- The dealer value showing 23 on initial load was investigated but determined to be
  likely correct (game-over state where all dealer cards are revealed). No code change
  needed for that path based on the analysis in the task description.
- Branch: `fix/blackjack-card-rendering`
