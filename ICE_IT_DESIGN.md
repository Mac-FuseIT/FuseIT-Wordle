# Ice.IT — Real-Time Multiplayer Ice Hockey

## Overview
Ice.IT is a live 1v1 (or NvN) ice hockey game where two players compete in real-time. Players control paddles to hit a puck into the opponent's goal. The game uses WebSockets via Cloudflare Durable Objects for low-latency synchronization.

---

## Game Mechanics

### Core Gameplay
- **Top-down view** of an ice rink (rectangular arena)
- **Two goals** — one at each end
- **Puck** — bounces off walls and paddles, scores when entering a goal
- **Paddles** — circular discs controlled by mouse/touch, constrained to player's half
- **Physics** — realistic collision detection, momentum, friction
- **Scoring** — first to win the configured number of rounds (best of 3/5/8/12/15/18/25)

### Controls
- **Mouse/Touch** — drag paddle within your half of the rink
- **Mobile-friendly** — touch controls with haptic feedback on collision

### Game Settings (configurable per session)
- **Best of**: 3, 5, 8, 12, 15, 18, 25 rounds
- **Puck speed**: Slow (0.5x), Normal (1x), Fast (1.5x), Turbo (2x)
- **Players per side**: 1, 2, 3 (default: 1)
  - Multi-player mode: each player controls one paddle, team coordination required

---

## Architecture

### Frontend (Flutter Web)
```
lib/ice/
├── screens/
│   ├── ice_lobby_screen.dart       # Session browser + create session
│   ├── ice_waiting_screen.dart     # Waiting for opponent
│   └── ice_game_screen.dart        # Live game canvas
├── widgets/
│   ├── ice_rink.dart               # Game canvas (CustomPainter)
│   ├── session_card.dart           # Lobby session list item
│   └── game_hud.dart               # Score, timer, settings display
├── services/
│   ├── ice_websocket.dart          # WebSocket connection manager
│   └── ice_physics.dart            # Client-side physics prediction
└── models/
    ├── game_state.dart             # Puck, paddles, score
    └── session.dart                # Session metadata
```

### Backend (Cloudflare)

#### Durable Object: `IceGameSession`
**Purpose**: Authoritative game server for one match. Handles physics, collision, scoring.

**State**:
- `sessionId` (UUID)
- `settings` (bestOf, puckSpeed, playersPerSide)
- `players` (WebSocket connections, team assignment)
- `gameState` (puck position/velocity, paddle positions, score, round)
- `status` (waiting | playing | finished)

**WebSocket Messages** (JSON):
```typescript
// Client → Server
{
  type: 'join',
  userId: string,
  name: string
}

{
  type: 'paddle_move',
  x: number,
  y: number
}

{
  type: 'ready'  // Signal ready to start
}

// Server → Client
{
  type: 'state',
  puck: { x, y, vx, vy },
  paddles: [{ id, x, y, team }],
  score: { team1, team2 },
  round: number,
  status: 'waiting' | 'playing' | 'round_end' | 'game_over'
}

{
  type: 'goal',
  team: 1 | 2,
  scorer: string
}

{
  type: 'player_joined',
  player: { id, name, team }
}

{
  type: 'error',
  message: string
}
```

**Game Loop** (server-side, 60 FPS):
1. Read paddle positions from latest client messages
2. Update puck physics (velocity, collisions with walls/paddles)
3. Check goal scoring
4. Broadcast `state` message to all clients (10 FPS to save bandwidth)

**Collision Detection**:
- Puck vs walls → reflect velocity
- Puck vs paddle → transfer momentum based on paddle velocity
- Paddle vs walls → clamp position to valid area

#### Functions API
```
functions/api/ice/
├── sessions.js          # GET /api/ice/sessions (list open sessions)
├── create.js            # POST /api/ice/create (create session, return sessionId)
└── join.js              # GET /api/ice/join/:sessionId (upgrade to WebSocket)
```

**D1 Tables**:
```sql
CREATE TABLE ice_sessions (
  session_id TEXT PRIMARY KEY,
  creator_id INTEGER,
  settings TEXT,  -- JSON: {bestOf, puckSpeed, playersPerSide}
  status TEXT,    -- 'waiting' | 'playing' | 'finished'
  created_at TEXT,
  started_at TEXT,
  finished_at TEXT
);

CREATE TABLE ice_matches (
  match_id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  winner_team INTEGER,
  final_score TEXT,  -- JSON: {team1, team2}
  duration_seconds INTEGER,
  created_at TEXT
);
```

---

## UI/UX Flow

### 1. Lobby Screen
**Layout**:
```
┌─────────────────────────────────────┐
│  Ice.IT                    [Back]   │
├─────────────────────────────────────┤
│                                     │
│  [Create Session]                   │
│                                     │
│  Open Sessions:                     │
│  ┌───────────────────────────────┐ │
│  │ Session #A3F2                 │ │
│  │ Best of 5 • Normal Speed      │ │
│  │ 1v1 • Waiting for opponent    │ │
│  │                        [Join] │ │
│  └───────────────────────────────┘ │
│  ┌───────────────────────────────┐ │
│  │ Session #B7E1                 │ │
│  │ Best of 3 • Fast Speed        │ │
│  │ 1v1 • Waiting for opponent    │ │
│  │                        [Join] │ │
│  └───────────────────────────────┘ │
│                                     │
└─────────────────────────────────────┘
```

**Create Session Dialog**:
```
┌─────────────────────────────────────┐
│  Create Ice.IT Session              │
├─────────────────────────────────────┤
│  Best of:                           │
│  [3] [5] [8] [12] [15] [18] [25]    │
│                                     │
│  Puck Speed:                        │
│  [Slow] [Normal] [Fast] [Turbo]     │
│                                     │
│  Players per side:                  │
│  [1] [2] [3]                        │
│                                     │
│         [Cancel]  [Create]          │
└─────────────────────────────────────┘
```

### 2. Waiting Screen
```
┌─────────────────────────────────────┐
│  Ice.IT                    [Leave]  │
├─────────────────────────────────────┤
│                                     │
│       Waiting for opponent...       │
│                                     │
│  Session ID: A3F2                   │
│  Best of 5 • Normal Speed • 1v1     │
│                                     │
│  Share link:                        │
│  fuseit-wordle.pages.dev/ice/A3F2   │
│                                     │
│            [Copy Link]              │
│                                     │
└─────────────────────────────────────┘
```

### 3. Game Screen
```
┌─────────────────────────────────────┐
│  Team 1: 2    Round 3/5    Team 2: 1│
├─────────────────────────────────────┤
│ ╔═══════════════════════════════╗   │
│ ║                               ║   │
│ ║  ┌─┐                          ║   │
│ ║  │ │         ●                ║   │  ← Puck
│ ║  └─┘                          ║   │  ← Paddle (Team 1)
│ ║ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ║   │  ← Center line
│ ║                          ┌─┐  ║   │
│ ║                          │ │  ║   │  ← Paddle (Team 2)
│ ║                          └─┘  ║   │
│ ╚═══════════════════════════════╝   │
│                                     │
│  [Leave Game]                       │
└─────────────────────────────────────┘
```

**Round End Overlay**:
```
┌─────────────────────────────────────┐
│                                     │
│         🏒 GOAL! 🏒                 │
│                                     │
│       Team 1 Scores!                │
│                                     │
│      Next round in 3...             │
│                                     │
└─────────────────────────────────────┘
```

**Game Over Screen**:
```
┌─────────────────────────────────────┐
│                                     │
│      🏆 Team 1 Wins! 🏆            │
│                                     │
│       Final Score: 3 - 1            │
│                                     │
│    [Play Again]  [Back to Lobby]    │
│                                     │
└─────────────────────────────────────┘
```

---

## Technical Implementation

### WebSocket Connection (Flutter)
```dart
class IceWebSocket {
  WebSocketChannel? _channel;
  final String sessionId;
  final Function(Map<String, dynamic>) onMessage;

  void connect() {
    final uri = 'wss://fuseit-wordle.pages.dev/api/ice/join/$sessionId';
    _channel = WebSocketChannel.connect(Uri.parse(uri));
    _channel!.stream.listen((data) {
      final msg = jsonDecode(data);
      onMessage(msg);
    });
  }

  void sendPaddleMove(double x, double y) {
    _channel?.sink.add(jsonEncode({
      'type': 'paddle_move',
      'x': x,
      'y': y,
    }));
  }

  void dispose() => _channel?.sink.close();
}
```

### Game Canvas (Flutter CustomPainter)
```dart
class IceRinkPainter extends CustomPainter {
  final GameState state;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw rink background (ice blue)
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), 
      Paint()..color = Color(0xFFD0E8F2));

    // Draw center line
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()..color = Colors.red..strokeWidth = 3,
    );

    // Draw goals
    _drawGoal(canvas, Offset(0, size.height / 2 - 40), true);
    _drawGoal(canvas, Offset(size.width, size.height / 2 - 40), false);

    // Draw puck
    canvas.drawCircle(
      Offset(state.puck.x, state.puck.y),
      8,
      Paint()..color = Colors.black,
    );

    // Draw paddles
    for (final paddle in state.paddles) {
      canvas.drawCircle(
        Offset(paddle.x, paddle.y),
        20,
        Paint()..color = paddle.team == 1 ? Colors.blue : Colors.red,
      );
    }
  }
}
```

### Durable Object (Cloudflare Worker)
```javascript
export class IceGameSession {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.sessions = new Map(); // WebSocket connections
  }

  async fetch(request) {
    const upgradeHeader = request.headers.get('Upgrade');
    if (upgradeHeader !== 'websocket') {
      return new Response('Expected WebSocket', { status: 426 });
    }

    const [client, server] = Object.values(new WebSocketPair());
    await this.handleSession(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  async handleSession(ws) {
    ws.accept();
    const playerId = crypto.randomUUID();
    this.sessions.set(playerId, { ws, paddle: { x: 0, y: 0 } });

    ws.addEventListener('message', (event) => {
      const msg = JSON.parse(event.data);
      if (msg.type === 'paddle_move') {
        this.sessions.get(playerId).paddle = { x: msg.x, y: msg.y };
      }
    });

    ws.addEventListener('close', () => {
      this.sessions.delete(playerId);
    });

    // Start game loop if 2 players
    if (this.sessions.size === 2 && !this.gameLoopRunning) {
      this.startGameLoop();
    }
  }

  startGameLoop() {
    this.gameLoopRunning = true;
    this.puck = { x: 400, y: 300, vx: 2, vy: 1 };
    
    setInterval(() => {
      this.updatePhysics();
      this.broadcast({
        type: 'state',
        puck: this.puck,
        paddles: Array.from(this.sessions.values()).map(s => s.paddle),
      });
    }, 16); // 60 FPS
  }

  updatePhysics() {
    // Move puck
    this.puck.x += this.puck.vx;
    this.puck.y += this.puck.vy;

    // Wall collisions
    if (this.puck.x < 0 || this.puck.x > 800) this.puck.vx *= -1;
    if (this.puck.y < 0 || this.puck.y > 600) this.puck.vy *= -1;

    // Paddle collisions (simplified)
    for (const session of this.sessions.values()) {
      const dx = this.puck.x - session.paddle.x;
      const dy = this.puck.y - session.paddle.y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < 28) { // puck radius + paddle radius
        this.puck.vx = dx / dist * 5;
        this.puck.vy = dy / dist * 5;
      }
    }
  }

  broadcast(msg) {
    const data = JSON.stringify(msg);
    for (const session of this.sessions.values()) {
      session.ws.send(data);
    }
  }
}
```

---

## Deployment Steps

1. **Add Durable Object binding** to `wrangler.toml`:
```toml
[[durable_objects.bindings]]
name = "ICE_GAME"
class_name = "IceGameSession"
script_name = "fuseit-wordle"

[[migrations]]
tag = "v1"
new_classes = ["IceGameSession"]
```

2. **Create API endpoints** in `functions/api/ice/`
3. **Build Flutter screens** in `frontend/lib/ice/`
4. **Add Ice.IT to main menu** in `main_menu_screen.dart`
5. **Deploy**: `npx wrangler pages deploy frontend/build/web`

---

## Future Enhancements
- **Power-ups**: speed boost, paddle size increase, multi-ball
- **Tournaments**: bracket-style competitions
- **Spectator mode**: watch live games
- **Replays**: save and replay matches
- **Leaderboard**: global rankings by wins
- **Custom rinks**: different arena shapes/obstacles
- **AI opponent**: single-player practice mode

---

## Performance Considerations
- **Client-side prediction**: smooth paddle movement even with latency
- **Server reconciliation**: authoritative puck position from server
- **Interpolation**: smooth puck movement between server updates
- **Bandwidth**: compress state updates, send deltas only
- **Latency**: target <50ms round-trip for responsive gameplay
