# Dev Notes — Solitaire API Service and Widgets

## Dart Developer Notes — solitaire service + base widgets

### Files Created
- `frontend/lib/solitaire/solitaire_service.dart` — Static HTTP client with `getToday`, `move`, `draw`, `recycle`, `giveUp`, `getLeaderboard` methods. All use Bearer token from SharedPreferences, return decoded JSON maps.
- `frontend/lib/solitaire/widgets/playing_card.dart` — Stateless card widget handling face-up, face-down, selected, and empty-slot states. White face with rank+suit text, green back from `theme.correct`, amber border glow when selected.
- `frontend/lib/solitaire/widgets/solitaire_help_dialog.dart` — AlertDialog with scrollable rules, controls, daily challenge, and scoring info. Matches the spec's Help Dialog Content section verbatim.

### Files Modified
None.

### Key Decisions
- `SolitaireService` uses the same static helper + inline `http.get`/`http.post` pattern as `CasinoLobbyScreen` (blackjack lobby). No new class hierarchy introduced.
- `PlayingCard` takes an `AppTheme` for the green back color (`theme.correct`) and amber selection glow (`theme.present`), consistent with how other widgets use theming in this codebase.
- Suit symbols use Unicode escape sequences (`\u2665` etc.) to avoid encoding issues.
- `_getRank` and `_getSuit` helper methods handle both 2-char cards ("Ah") and 3-char cards ("10s") correctly via `substring(0, length-1)` / `substring(length-1)`.

### Packages & Docs Consulted
- No new packages added. Uses `http` and `shared_preferences` already present in the project's `pubspec.yaml`.
- No Context7 lookups needed; APIs are straightforward and consistent with existing usage patterns.

### Analyze & Test Results
```
No errors
```
(Analyzer run on all three files — clean.)

### Open Issues
- Remaining widgets (`card_stack.dart`, `foundation_pile.dart`, `stock_waste.dart`) and screens (`solitaire_lobby_screen.dart`, `solitaire_game_screen.dart`) are out of scope for this sub-task.
- No tests exist in the project's Flutter frontend for any game — consistent with project norms.

---

## Dart Developer Notes — solitaire_lobby_screen.dart

### Files Created
- `frontend/lib/solitaire/solitaire_lobby_screen.dart` — `StatefulWidget` lobby for Deal.IT. Loads today's status and leaderboard on init, shows status card + play button + leaderboard. Navigates to `SolitaireGameScreen` when `_playing` is true.

### Files Modified
None.

### Key Decisions
- Followed the `CasinoLobbyScreen` pattern exactly: same `Column > Divider > Expanded > Center > ConstrainedBox(maxWidth:500) > SingleChildScrollView` skeleton.
- Header has `IconButton(arrow_back)` on the left, "Deal.IT" title in the `Expanded`, and `IconButton(help_outline)` on the right — matches the spec's "back arrow + title + ? help button (top right)" layout.
- Status card uses a `switch` on the `_status` string (`not_started` / `in_progress` / `won` / `gave_up`) and picks icon, color, and subtitle accordingly.
- Play button is green (`theme.correct`) when `_canPlay` and grey + disabled when status is `won` or `gave_up`.
- Daily leaderboard row: rank, nickname, points, moves, time. Monthly row: rank, nickname, total_points, games_won/games_played.
- `_completed` is derived from either `today['completed'] == true` or `status == 'won'` to handle both API response shapes gracefully.
- Used `(row['x'] as num?)?.toInt() ?? 0` throughout to safely cast JSON integers that may arrive as `int` or `double`.

### Packages & Docs Consulted
- No new packages. No Context7 or pub.dev lookups needed.

### Analyze & Test Results
```
No errors
```
(Analyzed `lib/solitaire/solitaire_lobby_screen.dart` and full `lib/solitaire/` directory — both clean.)

### Open Issues
- `solitaire_game_screen.dart` is imported but not yet created — analyzer passes because the file is referenced only as a direct import (no analysis of its symbols here). It will need to be created next to keep the build green.
