# Task: Implement Deal.IT (Daily Solitaire) for Fuse Arcade

## User Request
Implement a daily Klondike Solitaire (Draw 3) game called "Deal.IT" with server-validated moves, deterministic daily decks, tap-to-move interaction, scoring, and leaderboards. Full spec at `.workbench/solitaire/spec.md`.

## Codebase Summary
- **Stack**: Cloudflare Pages Functions (vanilla JS, ESM), D1 (SQLite), Flutter Web (Dart 3.11+, `http`, `shared_preferences`)
- **Structure**: `functions/api/<game>/` for backend endpoints, `frontend/lib/<game>/` for Flutter screens/widgets, `src/` for shared backend utilities, `migrations/` for D1 schema
- **Conventions**:
  - Backend: Each endpoint is a single JS file exporting `onRequestGet`/`onRequestPost` + `onRequestOptions` (CORS). Uses `requireAuth`, `getToday`, `jsonResponse`, `errorResponse` from `src/db.js`.
  - Frontend: Each game gets its own directory under `frontend/lib/`. Lobby screens take `theme`, `onBack`, `nickname`, `userId` props. Game screens are child widgets of the lobby (setState toggle, not Navigator). API calls use `http` package with Bearer token from `SharedPreferences`.
  - Routing: `AppView` enum in `main.dart`, each game gets one enum value that routes to its lobby screen. The lobby internally toggles to game screen.
  - Naming: Files are `snake_case.dart` (Flutter), `kebab-or-camel.js` (backend)
- **Critical Findings**: None. No blocking issues. The project has no test infrastructure for backend or frontend (no tests exist for any game).

## Relevant Files
| File | Read Before |
|------|-------------|
| `src/db.js` | Any backend work — shared auth/date/response helpers |
| `functions/api/blackjack/today.js` | Writing `today.js` — session create/get pattern |
| `functions/api/blackjack/bet.js` | Writing `move.js` — game logic, state update, save pattern |
| `functions/api/blackjack/leaderboard.js` | Writing `leaderboard.js` — daily/monthly query pattern + CORS |
| `migrations/0020_roulette.sql` | Writing migration — table + index pattern |
| `frontend/lib/blackjack/blackjack_lobby_screen.dart` | Writing lobby — API calls, status card, leaderboard display |
| `frontend/lib/blackjack/blackjack_screen.dart` | Writing game screen — state mgmt, API-driven UI updates |
| `frontend/lib/screens/main_menu_screen.dart` | Adding Deal.IT to menu — `_GameCard`, callbacks, `AppView` |
| `frontend/lib/main.dart` | Routing — `AppView` enum, switch expression |
| `.workbench/solitaire/spec.md` | Everything — the source of truth |

## Execution Plan

### Wave 1: Backend — Schema + Deck Generation + All API Endpoints

All backend files are independent of each other (they share only `src/db.js` and the new deck utility). Implement them all in one wave.

| Sub-task | Agent | Files | Details |
|----------|-------|-------|---------|
| Create D1 migration | developer | `migrations/0021_solitaire.sql` | Create `solitaire_sessions` and `solitaire_results` tables with indexes, exactly as specified in spec. |
| Create deck generation utility | developer | `src/solitaire-deck.js` | Implement `mulberry32` PRNG, `dateToSeed`, `generateDeck`, `dealGame` functions. Export all four. Use the exact algorithms from the spec. |
| Create GET /api/solitaire/today | developer | `functions/api/solitaire/today.js` | `onRequestGet`: auth check, get today's date via `getToday()`, check `solitaire_results` first (if exists, return completed state). Otherwise upsert into `solitaire_sessions` using `dealGame(today)`. Return sanitized state (hidden card counts, not actual values). Export `onRequestOptions` for CORS. |
| Create POST /api/solitaire/move | developer | `functions/api/solitaire/move.js` | `onRequestPost`: auth, load session, validate `status === 'in_progress'`, parse `from`/`to` zones. Implement full move validation (tableau↔tableau, waste→tableau, waste→foundation, tableau→foundation, foundation→tableau). After valid move: flip hidden cards, run auto-move logic (Aces/2s), check win condition, calculate points on win, save to `solitaire_results` if won. Set `started_at` on first move if null. Increment moves. Save state. Return sanitized state + `auto_moved` list + `won` flag. Export `onRequestOptions`. |
| Create POST /api/solitaire/draw | developer | `functions/api/solitaire/draw.js` | `onRequestPost`: auth, load session, validate stock non-empty, draw min(3, stock.length) from stock to waste. Set `started_at` if first action. Increment moves. Save state. Return drawn cards, counts. Export `onRequestOptions`. |
| Create POST /api/solitaire/recycle | developer | `functions/api/solitaire/recycle.js` | `onRequestPost`: auth, load session, validate stock empty + waste non-empty, reverse waste into stock, clear waste. Set `started_at` if first action. Increment moves. Save state. Export `onRequestOptions`. |
| Create POST /api/solitaire/give-up | developer | `functions/api/solitaire/give-up.js` | `onRequestPost`: auth, load session, validate in_progress, set status to `gave_up`, calculate time, calculate points (always 1 for give-up), insert into `solitaire_results`, save session. Export `onRequestOptions`. |
| Create GET /api/solitaire/leaderboard | developer | `functions/api/solitaire/leaderboard.js` | `onRequestGet`: auth, get today + monthStart, run daily query (points DESC, time ASC) and monthly query (total_points DESC, games_won DESC). Return `{ daily, monthly, date }`. Export `onRequestOptions`. |

### Wave 2: Frontend — Service + Widgets + Lobby + Game Screen + Menu Integration

All frontend files can be developed together since the service is a simple HTTP wrapper, widgets are leaf components, and the lobby/game screen compose them. The game screen depends on widgets, so the developer should create widgets first then compose them.

| Sub-task | Agent | Files | Details |
|----------|-------|-------|---------|
| Create solitaire API service | dart-developer | `frontend/lib/solitaire/solitaire_service.dart` | HTTP client class with methods: `getToday()`, `move(from, to)`, `draw()`, `recycle()`, `giveUp()`, `getLeaderboard()`. All use Bearer token from SharedPreferences, return decoded JSON maps. Follow pattern from existing API calls in lobby screens (inline `http.get`/`http.post`). |
| Create playing card widget | dart-developer | `frontend/lib/solitaire/widgets/playing_card.dart` | Stateless widget showing a single card. Props: `card` (String like "Ah"), `faceDown` (bool), `selected` (bool), `onTap` callback, `isEmpty` (bool, for empty slot). Size ~50×70, white face with rank+suit for face-up, green back for face-down, amber border when selected, dashed outline when empty. Red color for hearts/diamonds pips, black for clubs/spades. |
| Create card stack widget (tableau column) | dart-developer | `frontend/lib/solitaire/widgets/card_stack.dart` | Stateless widget rendering a vertical fan. Props: `hidden` (int count), `visible` (List<String> cards), `selectedIndex` (int? — index within visible, all from there to top highlight), `onCardTap(int index)` callback. Hidden cards show 15px of card back. Visible cards show 25px overlap, bottom card fully visible. Uses `PlayingCard` widget. |
| Create foundation pile widget | dart-developer | `frontend/lib/solitaire/widgets/foundation_pile.dart` | Stateless widget. Props: `suit` (String), `topCard` (String?), `count` (int), `onTap` callback, `selected` (bool). Shows suit symbol when empty, top card face-up when non-empty, count badge. |
| Create stock/waste widget | dart-developer | `frontend/lib/solitaire/widgets/stock_waste.dart` | Stateless widget. Props: `stockCount` (int), `wasteTop` (List<String>? — up to 3 cards fanned), `onStockTap` callback, `onWasteTap` callback, `wasteSelected` (bool). Stock: face-down pile with count, tappable. When empty: recycle icon. Waste: up to 3 fanned cards, only topmost tappable. |
| Create help dialog | dart-developer | `frontend/lib/solitaire/widgets/solitaire_help_dialog.dart` | Modal dialog with game rules, controls, scoring info. Content from spec's "Help Dialog Content" section. Match existing `help_dialog.dart` pattern. |
| Create lobby screen | dart-developer | `frontend/lib/solitaire/solitaire_lobby_screen.dart` | Props: `theme`, `onBack`, `nickname`, `userId`. Load today's status + leaderboard on init. Show status card (not started / in progress with move count / completed with points). Play button (disabled if completed). Leaderboard with daily/monthly tabs. Help (?) button top-right. Internal `_playing` bool state — when true, show `SolitaireGameScreen` instead. |
| Create game screen | dart-developer | `frontend/lib/solitaire/solitaire_game_screen.dart` | Props: `theme`, `onBack`, `nickname`, `userId`. The main board: header (back, moves, timer), stock+waste top-left, 4 foundations top-right, 7 tableau columns below, give-up button bottom. State: full game state from API, `_selectedCard` (zone+index), timer (elapsed from `started_at`). Tap-to-move logic: first tap selects, second tap attempts move via API. Stock tap calls draw. Empty stock tap calls recycle. Auto-move on Aces/2s (tap selects + auto-moves). Show confirmation dialog before give-up. Animate card flips and moves. On win: celebration overlay with points. |
| Wire into main menu + routing | dart-developer | `frontend/lib/screens/main_menu_screen.dart`, `frontend/lib/main.dart` | Add `AppView.solitaireGame` to enum. Add `onDealIT` callback to `MainMenuScreen`. Add `_GameCard(title: 'Deal.IT', subtitle: 'Daily solitaire', icon: Icons.style, ...)` in the Classic Games row. Add routing case in `main.dart` switch to show `SolitaireLobbyScreen`. |

### Wave 3: Review

| Sub-task | Agent | Details |
|----------|-------|---------|
| Review all backend code | reviewer | Verify move validation covers all edge cases (foundation→tableau, win detection, auto-move, timer logic, scoring formula). Check CORS on all endpoints. Check `started_at` only set on first action. Verify deck generation is deterministic. Check SQL queries match schema. |
| Review all frontend code | reviewer | Verify tap-to-move flow (select→destination→API call→update). Check responsive layout on mobile (portrait). Verify timer display updates. Check error handling on API failures. Verify widgets compose correctly. Check main menu integration doesn't break existing games. |

## Files Expected to Change

### New Files (Create)
- `migrations/0021_solitaire.sql`
- `src/solitaire-deck.js`
- `functions/api/solitaire/today.js`
- `functions/api/solitaire/move.js`
- `functions/api/solitaire/draw.js`
- `functions/api/solitaire/recycle.js`
- `functions/api/solitaire/give-up.js`
- `functions/api/solitaire/leaderboard.js`
- `frontend/lib/solitaire/solitaire_service.dart`
- `frontend/lib/solitaire/solitaire_lobby_screen.dart`
- `frontend/lib/solitaire/solitaire_game_screen.dart`
- `frontend/lib/solitaire/widgets/playing_card.dart`
- `frontend/lib/solitaire/widgets/card_stack.dart`
- `frontend/lib/solitaire/widgets/foundation_pile.dart`
- `frontend/lib/solitaire/widgets/stock_waste.dart`
- `frontend/lib/solitaire/widgets/solitaire_help_dialog.dart`

### Modified Files
- `frontend/lib/main.dart` — Add `AppView.solitaireGame`, add import, add switch case
- `frontend/lib/screens/main_menu_screen.dart` — Add `onDealIT` callback + `_GameCard`
