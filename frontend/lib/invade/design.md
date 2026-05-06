# Invade.IT — Design Document

## Overview
A single-player Space Invaders-style game. The player controls a spaceship, shoots descending enemy waves, and survives as long as possible. Score is saved to a leaderboard if it beats the player's personal best.

---

## Game Screen Layout

```
┌─────────────────────────────────────────────────────┐
│  Score: 1250          Lives: ♥ ♥          Level: 3  │
├─────────────────────────────────────────────────────┤
│                                                     │
│   👾👾👾👾👾👾👾👾   ← Enemy rows (move side to side) │
│   👾👾👾👾👾👾👾👾                                   │
│   👾👾👾👾👾👾👾👾                                   │
│                                                     │
│              💥  ← Enemy bullets falling            │
│                                                     │
│                    🚀  ← Player ship                │
│                    |   ← Player bullet              │
└─────────────────────────────────────────────────────┘
```

Canvas size: **800 × 600** (same as Pong.IT)

---

## Player

- Starts at bottom-center of canvas
- Moves **freely left/right** using **← →** arrow keys
- Shoots upward with **Spacebar** (one bullet at a time, or up to 2 simultaneous)
- Has **2 lives** (hit twice = game over)
- Visual: green spaceship icon (theme.correct color)
- On hit: brief flash animation, 1 second of invincibility

---

## Enemy Ships — 3 Tiers

| Tier | Name       | Rows | Points | HP | Color          | Fire Rate |
|------|------------|------|--------|----|----------------|-----------|
| 1    | Grunt      | 3    | 10     | 1  | theme.absent   | Low       |
| 2    | Soldier    | 2    | 25     | 1  | theme.present  | Medium    |
| 3    | Commander  | 1    | 50     | 2  | theme.correct  | High      |

- Enemies spawn in a **grid formation** at the top
- The entire grid moves **left → right → down → left** (classic invaders pattern)
- Movement speed increases as enemies are destroyed
- Enemies shoot bullets downward at random intervals based on their fire rate
- Commander enemies take **2 hits** to destroy (flash on first hit)

---

## Levels / Waves

| Level | Enemy Grid  | Speed Multiplier | Enemy Fire Rate |
|-------|-------------|------------------|-----------------|
| 1     | 3 rows      | 1×               | Slow            |
| 2     | 4 rows      | 1.3×             | Medium          |
| 3     | 5 rows      | 1.6×             | Medium-High     |
| 4+    | 5 rows      | 2×+              | High            |

- When all enemies in a wave are destroyed → next level starts
- Level number shown in HUD
- Brief "Level X" overlay shown between waves

---

## Scoring

| Action                  | Points |
|-------------------------|--------|
| Destroy Grunt           | 10     |
| Destroy Soldier         | 25     |
| Destroy Commander       | 50     |
| Clear entire wave       | +100 bonus |

- Score displayed live in HUD
- Personal best stored in D1 database per user
- Score only submitted if it **beats** the player's previous best

---

## Game Over Screen

```
┌──────────────────────────────┐
│        GAME OVER             │
│                              │
│   Your Score:  1,450         │
│   Best Score:  2,100         │
│                              │
│   [Play Again]  [Leaderboard]│
└──────────────────────────────┘
```

- Shows for 5 seconds then auto-returns to menu
- If score > personal best: "New High Score! 🎉" message
- Score submitted to leaderboard automatically

---

## Leaderboard

- Global top scores across all players
- Columns: Rank | Nickname | Score | Level Reached | Date
- Accessible from main menu and game over screen
- Same styling as Guess.IT leaderboard

---

## Controls

| Key         | Action          |
|-------------|-----------------|
| ← Arrow     | Move left        |
| → Arrow     | Move right       |
| Spacebar    | Shoot            |

- Uses `HardwareKeyboard.instance.addHandler` (same as Pong.IT — proven to work on Flutter web)

---

## Architecture

### Frontend (Flutter)
```
frontend/lib/invade/
├── screens/
│   ├── invade_lobby_screen.dart     # Main menu / leaderboard entry
│   └── invade_game_screen.dart      # Game canvas + HUD
├── models/
│   ├── player.dart                  # Player state (x, lives, bullets)
│   ├── enemy.dart                   # Enemy state (x, y, tier, hp)
│   └── bullet.dart                  # Bullet state (x, y, direction)
└── painters/
    └── invade_painter.dart          # CustomPainter for all game objects
```

### Backend (Cloudflare)
```
functions/api/invade/
├── score.js        # POST — submit score if personal best
└── leaderboard.js  # GET  — top scores
```

### Database (D1)
```sql
CREATE TABLE invade_scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  score INTEGER NOT NULL,
  level_reached INTEGER NOT NULL,
  achieved_at TEXT NOT NULL,
  UNIQUE(user_id)  -- one row per user, updated on new best
);
```

---

## Game Loop

- Runs at **60fps** using Flutter `Ticker` (same as Pong.IT)
- All physics computed client-side (no server needed — single player)
- State: player position, enemy positions, bullets, score, lives, level
- On each tick:
  1. Move player (if key held)
  2. Move player bullets up
  3. Move enemy grid (side-to-side + down)
  4. Move enemy bullets down
  5. Check collisions (player bullet ↔ enemy, enemy bullet ↔ player)
  6. Spawn enemy bullets randomly
  7. Check win condition (all enemies dead → next level)
  8. Check lose condition (player lives = 0 OR enemies reach bottom)

---

## Visual Style

- Matches existing FuseIT theme (dark background, theme colors)
- WavyBackground behind game canvas
- Enemy ships drawn with `CustomPainter` using simple geometric shapes
- Player ship: triangle/rocket shape in `theme.correct`
- Bullets: small rectangles
- Explosions: brief circle expand animation on enemy death
- HUD: score top-left, lives top-center, level top-right
