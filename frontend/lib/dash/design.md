# Dash.IT — Design Document

## Overview
A daily side-scrolling platformer in the spirit of Super Dash. Each day a new level is generated offline and stored in D1. Players have one attempt per day to complete the level. The level is designed to take 3–5 minutes and includes platforming challenges, puzzles, enemies, and collectibles. A daily leaderboard ranks players by completion time and coins collected.

---

## Game Canvas

- Canvas size: **1200 × 500** (wider than tall for side-scrolling)
- Level width: **6000px** (5× canvas width — scrolls horizontally)
- Camera follows player, clamped to level bounds
- Tile size: **40 × 40px**
- Grid: 150 columns × 12 rows

---

## Player

| Property     | Value                          |
|--------------|-------------------------------|
| Size         | 32 × 40px                     |
| Start        | Column 2, standing on ground  |
| Move speed   | 4px/tick                      |
| Jump height  | ~3.5 tiles                    |
| Max jumps    | 1 (no double jump)            |
| Lives        | 3 (hit by enemy = lose 1 life)|
| Stomp        | Jump on enemy = kill it       |

### Controls
| Key          | Action        |
|--------------|---------------|
| ← →          | Move left/right |
| Space / ↑    | Jump           |
| ↓            | Duck / enter pipe |

---

## Tile Types

| ID | Name          | Description                                      |
|----|---------------|--------------------------------------------------|
| 0  | Air           | Empty space                                      |
| 1  | Ground        | Solid brown/green ground block                   |
| 2  | Brick         | Breakable brick (stomp from below to break)      |
| 3  | Question Block| Hit from below: drops coin or power-up           |
| 4  | Solid Block   | Indestructible grey block                        |
| 5  | Pipe (top)    | Decorative or warp pipe entrance                 |
| 6  | Pipe (body)   | Pipe body tile                                   |
| 7  | Coin          | Collectible (+10 pts each)                       |
| 8  | Platform      | Floating one-way platform (land on top only)     |
| 9  | Spike         | Instant death on contact                         |
| 10 | Lava          | Instant death, fills pit bottoms                 |
| 11 | Flag Pole     | Level end — touch to complete                    |
| 12 | Moving Platform | Horizontally or vertically moving platform    |
| 13 | Spring        | Launches player upward (2× jump height)          |
| 14 | Ice Block     | Slippery surface (reduced friction)              |
| 15 | Warp Pipe     | Enter with ↓ to teleport to linked pipe          |

---

## Power-Ups (from Question Blocks)

| Item         | Effect                                      | Probability |
|--------------|---------------------------------------------|-------------|
| Mushroom     | Grow big — survive one hit                  | 40%         |
| Fire Flower  | Shoot fireballs (Space while big)           | 25%         |
| Star         | Invincibility for 8 seconds                 | 10%         |
| Coin         | Just a coin                                 | 25%         |

---

## Enemies

| Name        | Behaviour                                      | Points | Kill Method         |
|-------------|------------------------------------------------|--------|---------------------|
| Goomba      | Walks left/right, turns at edges               | 100    | Stomp or fireball   |
| Koopa       | Walks, retreats into shell when stomped; shell slides and kills others | 200 | Stomp (→ shell), fireball |
| Piranha Plant | Pops out of pipe periodically              | 200    | Fireball only       |
| Spiny       | Walks like Goomba but cannot be stomped        | 150    | Fireball only       |
| Buzzy Beetle| Like Koopa but fireproof                       | 150    | Stomp only          |
| Hammer Bro  | Throws hammers in arcs at player               | 300    | Stomp or fireball   |
| Chain Chomp | Lunges on chain toward player                  | 0      | Avoid only          |
| Boo         | Moves toward player when not looked at (facing away) | 200 | Star only        |

---

## Puzzles & Challenges

Each generated level includes a selection of these challenge segments:

### 1. Coin Trail Puzzle
A sequence of coins arranged to guide the player through a non-obvious path (e.g., through a hidden gap or over a wall).

### 2. Moving Platform Gauntlet
A section with 4–6 moving platforms over a lava pit. Platforms move at different speeds and directions.

### 3. Pipe Maze
2–3 warp pipes that teleport the player to different sections. One path leads forward, others loop back or drop into a pit.

### 4. Enemy Gauntlet
A flat section with 5–8 enemies in sequence, requiring precise stomping or fireball use to clear.

### 5. Vertical Climb
A tall section requiring the player to jump between narrow platforms to reach a high passage.

### 6. Spike Corridor
A low-ceiling corridor with spikes on the floor and ceiling, requiring precise ducking and timing.

### 7. Blind Jump
A gap where the landing platform is off-screen — coins hint at the correct trajectory.

### 8. Hammer Bro Blockade
A narrow bridge guarded by a Hammer Bro — must be defeated or bypassed to proceed.

### 9. Underground Section
A warp pipe leads to a dark underground bonus room full of coins and a Buzzy Beetle, then exits further ahead.

### 10. Final Castle Rush
The last 20% of the level is a castle-themed section with Hammer Bros, Chain Chomps, and a flag pole finish.

---

## Level Structure

Each level is divided into **5 zones** (each ~1200px wide = 1 screen):

| Zone | Theme         | Challenge Type                        |
|------|---------------|---------------------------------------|
| 1    | Grassland     | Tutorial-style, Goombas, coin trails  |
| 2    | Underground   | Pipe maze, Buzzy Beetles, tight jumps |
| 3    | Sky/Clouds    | Moving platforms, Spinies, vertical climb |
| 4    | Desert/Ice    | Slippery ice blocks, spike corridors  |
| 5    | Castle        | Hammer Bros, Chain Chomps, flag pole  |

---

## Scoring

| Action                  | Points  |
|-------------------------|---------|
| Collect coin            | 10      |
| Kill Goomba             | 100     |
| Kill Koopa              | 200     |
| Kill Hammer Bro         | 300     |
| Shell kill (chain)      | 200×chain|
| Complete level          | 1000    |
| Time bonus              | max 500 (decreases per second) |
| Lives remaining         | 200 per life |

---

## Daily Leaderboard

- Ranked by: **total score** (completion + coins + kills + time bonus)
- Columns: Rank | Nickname | Score | Time | Coins | Date
- Only completions count — dying and not finishing = no score
- Resets daily

---

## Architecture

### Frontend (Flutter)
```
frontend/lib/dash/
├── screens/
│   ├── dash_lobby_screen.dart    # Daily level info, leaderboard, play button
│   └── dash_game_screen.dart     # Game canvas, HUD, game loop
├── models/
│   ├── level.dart                 # Level data (tiles, enemies, coins, pipes)
│   ├── player.dart                # Player physics state
│   ├── enemy.dart                 # Enemy state + AI
│   └── tile.dart                  # Tile types and properties
└── painters/
    └── dash_painter.dart         # CustomPainter for all game objects
```

### Backend (Cloudflare Pages Functions)
```
functions/api/dash/
├── today.js          # GET — fetch today's level from D1
├── complete.js       # POST — submit completion score
└── leaderboard.js    # GET — today's leaderboard
```

### Database (D1)
```sql
CREATE TABLE dash_levels (
  date TEXT PRIMARY KEY,           -- 'YYYY-MM-DD'
  level_data TEXT NOT NULL,        -- JSON: tiles, enemies, coins, pipes, platforms
  created_at TEXT NOT NULL
);

CREATE TABLE dash_scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  nickname TEXT NOT NULL,
  score INTEGER NOT NULL,
  time_seconds INTEGER NOT NULL,
  coins INTEGER NOT NULL,
  completed_at TEXT NOT NULL,
  UNIQUE(user_id, date)            -- one score per player per day
);
```

---

## Level Generator Script

A standalone Node.js script run locally to pre-generate levels:

```
scripts/generate-dash-levels.js
```

### Usage
```bash
node scripts/generate-dash-levels.js --days 30 --start 2026-05-07
```

This generates 30 days of levels starting from the given date and inserts them into D1 via the Wrangler API.

### Generation Algorithm

```
For each day:
1. Seed RNG with date string (deterministic per day)
2. Build 150×12 tile grid, fill bottom 2 rows with ground
3. For each of 5 zones (30 cols each):
   a. Pick 2 challenge types randomly (from the 10 types above)
   b. Stamp challenge templates into the grid
   c. Place enemies appropriate to zone theme
   d. Scatter coins along viable paths
   e. Add question blocks at reachable heights
4. Place warp pipes connecting underground section
5. Place flag pole at column 148
6. Validate: ensure path from start to end is completable
   (simple BFS over reachable tiles)
7. Serialize to JSON and insert into D1
```

### Level JSON Format
```json
{
  "width": 150,
  "height": 12,
  "tiles": [[0,0,...], ...],
  "enemies": [
    {"type": "goomba", "x": 5, "y": 9},
    {"type": "koopa", "x": 12, "y": 9}
  ],
  "movingPlatforms": [
    {"x": 40, "y": 6, "width": 3, "axis": "x", "range": 4, "speed": 1}
  ],
  "warpPipes": [
    {"entrance": {"x": 20, "y": 8}, "exit": {"x": 80, "y": 8}}
  ],
  "questionBlocks": [
    {"x": 8, "y": 7, "content": "mushroom"}
  ]
}
```

---

## Visual Style

- Matches FuseIT theme colors:
  - Ground/bricks: dark with `theme.absent` tint
  - Coins: `theme.present` (yellow)
  - Player: `theme.correct` (green) rocket-style sprite
  - Enemies: distinct shapes per type using CustomPainter
  - Question blocks: `theme.correct` with `?` text
  - Background: layered parallax (sky, clouds, mountains) using `theme.background`
- HUD: lives top-left, score top-center, timer top-right (inside canvas)
- WavyBackground behind the canvas frame

---

## Game Loop

- 60fps via Flutter `Ticker`
- Per tick:
  1. Apply gravity to player
  2. Move player (keyboard input)
  3. Resolve tile collisions (AABB)
  4. Move enemies (AI)
  5. Resolve enemy collisions
  6. Move moving platforms
  7. Check coin/power-up collection
  8. Check pipe entry (↓ held over pipe)
  9. Check death conditions (fall, spike, lava, enemy)
  10. Check win condition (reach flag pole)
  11. Scroll camera to follow player
  12. Decrement time bonus counter

---

## Daily Flow

1. Player opens Dash.IT → sees today's level name/theme and leaderboard
2. Clicks **Play** → level loads from D1
3. Plays level (3–5 min target)
4. On completion → score submitted, leaderboard updates
5. On death (0 lives) → game over screen, no score submitted
6. Player can watch a "replay" of their run (stretch goal)
