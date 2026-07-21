# Solitaire Dev Notes

## Dart Developer Notes — menu-wiring

### Files Modified
- `frontend/lib/main.dart` — Added `solitaireGame` to `AppView` enum; imported `SolitaireLobbyScreen`; added `onDealIT` callback to `MainMenuScreen` constructor call; added routing case for `AppView.solitaireGame` → `SolitaireLobbyScreen`
- `frontend/lib/screens/main_menu_screen.dart` — Added `onDealIT` `VoidCallback` field and required constructor param; added "Klond.IT" `_GameCard` to the Classic Games row with `Icons.layers` and `theme.present` colour

### Key Decisions
- Named callback `onDealIT` to match the in-game branding ("Klond.IT") and mirror the existing naming convention (`onBlackjackIT`, `onChessIT`, etc.)
- Used `Icons.layers` icon for Klond.IT — visually evokes a deck of cards, distinct from `Icons.style` already used by Gamble.IT
- Used `theme.present` colour to alternate with `theme.correct` in the Classic Games row, matching the alternating pattern already used (Invade.IT = correct, Chess.IT = present, Gamble.IT = correct → Klond.IT = present)
- `SolitaireLobbyScreen` takes identical params to `ChessLobbyScreen` / `CasinoLobbyScreen` so no adapter layer needed

### Packages & Docs Consulted
None — no new packages added. Pattern was read directly from existing source files.

### Analyze & Test Results
`analyze_files` on both files: **No errors**

### Open Issues
None — wiring is complete and clean.

## Dart Developer Notes — SolitaireGameScreen

### Files Created
- `frontend/lib/solitaire/solitaire_game_screen.dart` — Main game board: state management, tap-to-move interaction loop, stock/waste/foundation/tableau rendering, timer, give-up dialog, result screen.

### Key Decisions
- **Selection model**: `_Selection` value class carries zone + col + cardIndex + suit + card. Allows checking "tap same card → deselect" and building API payloads cleanly.
- **Tableau highlighting**: all visible cards at index >= selectedCard.cardIndex in the same column are shown selected (matches "select stack" rule).
- **Waste fan**: renders up to 3 waste cards fanned with 14px horizontal offset; only topmost is tappable.
- **Empty column tap**: renders `PlayingCard(isEmpty: true)` as a tappable King-drop target.
- **Result screen**: replaces game board when status is `won` or `gave_up`; shows points/moves/time.
- **Timer**: `Timer.periodic` runs every second in state; only increments when `_started && _status == 'in_progress'`.
- **Column height**: computed as `hidden * 12 + (visible.length-1) * 22 + 70` so the Stack has a real height and doesn't clip.
- Kept under ~800 lines (file is 788 lines with blank lines/comments).

### Packages & Docs Consulted
- Read spec.md, solitaire_service.dart, playing_card.dart, app_theme.dart directly — no external docs needed.

### Analyze & Test Results
- `analyze_files`: **No errors**
- Tests: no unit tests added (UI-only widget; integration testing requires running device).

### Open Issues
- No move animation (card slides) — deferred to v2 per spec non-goal.
- Auto-move shortcut (tap Ace → auto-foundation) not wired client-side; server handles auto-move after each POST /move response via `auto_moved` field — client currently ignores that field (no animation).
- `wasteCount` tracked locally from draw/recycle responses but not used for UI display currently (waste fan uses `_wasteTop` list length).

## Dart Developer Notes — Fix header width and centering

### Files Modified
- `frontend/lib/solitaire/solitaire_game_screen.dart` — moved `_buildHeader()` outside `Center > ConstrainedBox`, updated `_buildBody()` to live inside `Expanded > Center > ConstrainedBox`, added second `Spacer()` to center moves/time

### Key Decisions
- `build()` restructured: header now sits in a top-level `Column` above an `Expanded` that contains the `Center > ConstrainedBox > _buildBody()` so the header spans full screen width
- Two `Spacer()` widgets in the header `Row` (one after title, one after time) symmetrically push moves+time to the horizontal center
- Added `width: double.infinity` to the header `Container` for explicit full-width guarantee
- Increased `SizedBox` gap between Moves and timer icon from 12 → 16 to match spec

### Packages & Docs Consulted
None — pure Flutter layout change.

### Analyze & Test Results
`analyze_files` → No errors

### Open Issues
None.

## Dart Developer Notes — fix card stacking overlap visibility

### Files Modified
- `frontend/lib/solitaire/widgets/playing_card.dart` — Replaced centered two-text layout (rank + suit on separate lines, `mainAxisAlignment: center`) with a single `Padding(left:4, top:3)` + `Column(crossAxisAlignment: start)` showing `"$rank$suitSymbol"` (e.g. "5♦") in the top-left corner. Removed unused `pipColor` variable.
- `frontend/lib/solitaire/solitaire_game_screen.dart` — Increased `visibleOverlap` constant from `22.0` to `25.0` for slightly more breathing room between stacked face-up cards.

### Key Decisions
- Combined rank and suit symbol into one `Text` widget (`"$rank$suitSymbol"`) rather than keeping two separate widgets — simpler and fits the narrow 25px visible strip.
- Top-left positioning ensures the label is always visible in the exposed strip of each stacked card regardless of overlap amount.

### Packages & Docs Consulted
- None — pure widget layout change, no new packages.

### Analyze & Test Results
- `analyze_files` on both files: **No errors**
- Committed on `feat/solitaire` as `f2b5ed4`

### Open Issues
- None.

## Dart Developer Notes — fix-bg-header: remove Scaffold, standard header style

### Files Modified
- `frontend/lib/solitaire/solitaire_game_screen.dart` — Removed own `Scaffold` + `SafeArea`; `build()` now returns a plain `Column` (or `_buildResultScreen()` Column). Updated `_buildHeader()` to match the blackjack/roulette pattern: transparent background, `Padding(horizontal:16, vertical:12)`, white text, `Colors.white70` stats. Added `Divider(color: Color(0xFF3A3A3C), height:1)` below header. `_buildResultScreen()` now returns a full `Column` with header + divider + centered content, instead of a bare `Center`. Removed dead result-check from `_buildBody()`.

### Key Decisions
- `build()` short-circuits to `_buildResultScreen()` when status is won/gave_up, so the result view still shows the consistent header + wavy background from the parent Scaffold.
- Kept `_buildResultScreen()` as a separate method (rather than inlining into `build()`) for readability and to match the task spec.
- Removed the extra trailing `Spacer()` from the header Row — single `Spacer()` after the title pushes stats to the right, matching blackjack exactly.
- No new packages introduced.

### Packages & Docs Consulted
- None — read `blackjack_screen.dart` directly for the reference pattern.

### Analyze & Test Results
- `analyze_files` on `lib/solitaire/solitaire_game_screen.dart`: **No errors**
- Committed on `feat/solitaire` as `80a583d`

### Open Issues
- None.

## Dart Developer Notes — compact card display (fully visible vs overlapped)

### Files Modified
- `frontend/lib/solitaire/widgets/playing_card.dart` — added `compact` prop (default `false`). When `true`, renders rank+suit top-left (compact, for overlapped cards). When `false`, renders rank and suit symbol centered (for fully visible cards).
- `frontend/lib/solitaire/solitaire_game_screen.dart` — `_buildVisibleCard` passes `compact: i < visible.length - 1` so only the bottom (fully visible) tableau card gets the centered layout. Waste pile fanned cards get `compact: true`; the top (playable) card gets `compact: false`.

### Key Decisions
- Default for `compact` is `false` (centered), so foundation cards and any other standalone usages automatically show the full centered layout without needing a change.
- The `compact` condition in waste is `i < topIndex` which is equivalent to "not the last card" — consistent with the tableau logic.

### Packages & Docs Consulted
None — pure Flutter widget change, no third-party packages involved.

### Analyze & Test Results
`analyze_files` → No errors on both files.

### Open Issues
None.

## Dart Developer Notes — subtle theme.present border for interactive cards

### Files Modified
- `frontend/lib/solitaire/widgets/playing_card.dart` — updated face-up card border logic

### What Changed
The `border` property inside the face-up card `BoxDecoration` was updated from a two-way toggle (selected vs grey) to a three-way expression:

| State | Border color | Width |
|---|---|---|
| `selected == true` | `theme.present` (solid) | 2 |
| `selected == false && compact == false` | `theme.present.withOpacity(0.5)` | 1 |
| `selected == false && compact == true` | `Colors.grey.shade300` | 1 |

### Key Decisions
- Used inline ternary inside `Border.all(color: …)` — consistent with the pre-existing style in the file.
- No change to `boxShadow` or any other property.

### Packages & Docs Consulted
None — pure logic change using existing Flutter/Dart APIs.

### Analyze & Test Results
`analyze_files` → **No errors**

### Open Issues
None.

## Dart Developer Notes — reorganize-menu: Classic Games + The Lounge

### Files Modified
- `frontend/lib/screens/main_menu_screen.dart` — Replaced single "Classic Games" row (4 cards: Invade.IT, Chess.IT, Gamble.IT, Klond.IT) with two distinct sections:
  - **Classic Games**: Invade.IT + Klond.IT
  - **The Lounge** (new section): Chess.IT + Gamble.IT
  - Column order is now: Word Games → Classic Games → The Lounge → footer

### Key Decisions
- Removed commented-out Pong.IT cards (were dead code inside the old row).
- Renamed section comment from `// Arcade Games` to `// Classic Games` to match the visible heading.
- Added `const SizedBox(height: 32)` between Classic Games and The Lounge — matches the existing spacing between Word Games and Classic Games.
- No new widgets, packages, or callbacks added — all existing `onTap` callbacks were already wired.

### Packages & Docs Consulted
None — pure layout restructure using existing code.

### Analyze & Test Results
`analyze_files` on `lib/screens/main_menu_screen.dart`: **No errors**

### Open Issues
None.

## Developer Notes — add reserve slot to solitaire backend

### Files Modified
- `src/solitaire-deck.js` — Added `reserve: null` to the `dealGame` return object so all new sessions start with an empty reserve slot.
- `functions/api/solitaire/today.js` — Added `reserve: state.reserve || null` to the GET response after `waste_count`, so the client knows the current reserve card on load.
- `functions/api/solitaire/move.js` — Full reserve support:
  - **Source extraction**: Added `from.zone === 'reserve'` branch that sets `movingCards = [state.reserve]` (errors if reserve is empty).
  - **Tableau destination**: Added `from.zone === 'reserve'` case in the "remove from source" block to clear `state.reserve = null` on successful move.
  - **Foundation destination**: Same — added `from.zone === 'reserve'` case to clear `state.reserve = null`.
  - **Reserve destination**: New `to.zone === 'reserve'` destination block with rules: single card only, reserve must be empty, card must come from waste. Sets `state.reserve = movingCards[0]` and pops the waste on success.
  - **Response**: Added `reserve: state.reserve` to the state object in the move response.

### Key Decisions
- Reserve can only be filled from waste (not from tableau), keeping the mechanic constrained and balanced.
- Reserve can be moved to either tableau or foundation, giving maximum utility.
- `state.reserve` is stored as a raw card string (e.g. `"5h"`) matching the existing card format throughout the codebase.
- `reserve: null` is the sentinel for empty — consistent with how it's initialised in `dealGame`.

### Library Docs Consulted (Context7)
None — no third-party libraries touched; pure JS logic change.

### Build & Test Results
- `node --check` on all 3 files: **no syntax errors**
- Committed: `9d429a8` — `feat(solitaire): add reserve slot to backend state and move logic`

### Open Issues
None.
