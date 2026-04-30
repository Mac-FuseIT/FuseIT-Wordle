// Ice.IT Game Session - Durable Object
// Authoritative server for one live match
export class IceGameSession {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.players = new Map();
    this.puck = { x: 400, y: 300, vx: 0, vy: 0 };
    this.score = { team1: 0, team2: 0 };
    this.round = 1;
    this.status = 'waiting';
    this.settings = { bestOf: 5, puckSpeed: 1, playersPerSide: 1 };
    this.gameLoopInterval = null;
    this.sessionId = null;
  }

  async fetch(request) {
    const url = new URL(request.url);
    
    if (url.pathname.endsWith('/websocket')) {
      const upgradeHeader = request.headers.get('Upgrade');
      if (upgradeHeader !== 'websocket') {
        return new Response('Expected WebSocket', { status: 426 });
      }
      const [client, server] = Object.values(new WebSocketPair());
      await this.handleSession(server, request);
      return new Response(null, { status: 101, webSocket: client });
    }

    if (url.pathname.endsWith('/settings')) {
      const settings = await request.json();
      this.settings = settings;
      this.sessionId = settings.sessionId;
      return new Response(JSON.stringify({ ok: true }), { headers: { 'Content-Type': 'application/json' } });
    }

    return new Response('Not found', { status: 404 });
  }

  async handleSession(ws, request) {
    ws.accept();
    const playerId = crypto.randomUUID();
    const team = this.players.size === 0 ? 1 : 2;
    
    this.players.set(playerId, {
      ws,
      team,
      paddle: { x: team === 1 ? 100 : 700, y: 300 },
      name: 'Player ' + (this.players.size + 1),
    });

    ws.send(JSON.stringify({ type: 'joined', playerId, team }));
    this.broadcastLobbyState();

    ws.addEventListener('message', (event) => {
      try {
        const msg = JSON.parse(event.data);
        this.handleMessage(playerId, msg);
      } catch (e) {}
    });

    ws.addEventListener('close', () => {
      this.players.delete(playerId);
      if (this.players.size === 0 && this.gameLoopInterval) {
        clearInterval(this.gameLoopInterval);
        this.gameLoopInterval = null;
      }
      this.broadcastLobbyState();
    });
  }

  handleMessage(playerId, msg) {
    const player = this.players.get(playerId);
    if (!player) return;

    if (msg.type === 'set_name') {
      player.name = msg.name;
      this.broadcastLobbyState();
    } else if (msg.type === 'paddle_move') {
      const halfWidth = 400;
      if (player.team === 1) {
        player.paddle.x = Math.max(20, Math.min(halfWidth - 20, msg.x));
      } else {
        player.paddle.x = Math.max(halfWidth + 20, Math.min(800 - 20, msg.x));
      }
      player.paddle.y = Math.max(20, Math.min(600 - 20, msg.y));
    } else if (msg.type === 'switch_team') {
      player.team = player.team === 1 ? 2 : 1;
      player.paddle.x = player.team === 1 ? 100 : 700;
      this.broadcastLobbyState();
    } else if (msg.type === 'start_game') {
      if (this.players.size >= 2 && this.status === 'waiting') {
        this.startGame();
      }
    }
  }

  broadcastLobbyState() {
    const players = Array.from(this.players.values()).map((p, i) => ({
      id: Array.from(this.players.keys())[i],
      name: p.name,
      team: p.team,
    }));
    this.broadcast({
      type: 'lobby_state',
      players,
      settings: this.settings,
    });
  }

  startGame() {
    this.status = 'playing';
    this.resetPuck();
    this.broadcast({ type: 'game_start' });
    
    this.gameLoopInterval = setInterval(() => {
      this.updatePhysics();
      this.broadcastState();
    }, 16); // 60 FPS
  }

  resetPuck() {
    this.puck = {
      x: 400,
      y: 300,
      vx: (Math.random() - 0.5) * 4 * this.settings.puckSpeed,
      vy: (Math.random() - 0.5) * 4 * this.settings.puckSpeed,
    };
  }

  updatePhysics() {
    this.puck.x += this.puck.vx;
    this.puck.y += this.puck.vy;

    // Wall collisions (top/bottom)
    if (this.puck.y < 8 || this.puck.y > 592) {
      this.puck.vy *= -0.95;
      this.puck.y = Math.max(8, Math.min(592, this.puck.y));
    }

    // Goal detection
    if (this.puck.x < 8) {
      this.score.team2++;
      this.onGoal(2);
      return;
    }
    if (this.puck.x > 792) {
      this.score.team1++;
      this.onGoal(1);
      return;
    }

    // Paddle collisions
    for (const player of this.players.values()) {
      const dx = this.puck.x - player.paddle.x;
      const dy = this.puck.y - player.paddle.y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < 28) {
        const angle = Math.atan2(dy, dx);
        this.puck.vx = Math.cos(angle) * 6 * this.settings.puckSpeed;
        this.puck.vy = Math.sin(angle) * 6 * this.settings.puckSpeed;
        this.puck.x = player.paddle.x + Math.cos(angle) * 28;
        this.puck.y = player.paddle.y + Math.sin(angle) * 28;
      }
    }

    // Friction
    this.puck.vx *= 0.995;
    this.puck.vy *= 0.995;
  }

  async onGoal(team) {
    this.broadcast({ type: 'goal', team, score: this.score });
    const maxScore = Math.ceil(this.settings.bestOf / 2);
    if (this.score.team1 >= maxScore || this.score.team2 >= maxScore) {
      this.status = 'finished';
      const winner = this.score.team1 > this.score.team2 ? 1 : 2;
      this.broadcast({ type: 'game_over', winner, score: this.score });
      clearInterval(this.gameLoopInterval);
      this.gameLoopInterval = null;
      
      // Mark session as finished in D1
      if (this.sessionId) {
        await this.env.DB.prepare("UPDATE ice_sessions SET status = 'finished' WHERE session_id = ?")
          .bind(this.sessionId).run();
      }
      
      // Close all connections after 5 seconds
      setTimeout(() => {
        for (const player of this.players.values()) {
          try { player.ws.close(); } catch (e) {}
        }
        this.players.clear();
      }, 5000);
    } else {
      this.round++;
      this.resetPuck();
    }
  }

  broadcastState() {
    const paddles = Array.from(this.players.values()).map(p => ({
      x: p.paddle.x,
      y: p.paddle.y,
      team: p.team,
    }));
    this.broadcast({
      type: 'state',
      puck: this.puck,
      paddles,
      score: this.score,
      round: this.round,
      status: this.status,
    });
  }

  broadcastPlayerList() {
    const players = Array.from(this.players.values()).map(p => ({ name: p.name, team: p.team }));
    this.broadcast({ type: 'players', players });
  }

  broadcast(msg) {
    const data = JSON.stringify(msg);
    for (const player of this.players.values()) {
      try { player.ws.send(data); } catch (e) {}
    }
  }
}
