import { DurableObject } from 'cloudflare:workers';

export class PongGameSession extends DurableObject {
  constructor(state, env) {
    super(state, env);
    this.state = state;
    this.env = env;
    this.players = new Map();
    this.creatorName = null;
    this.sessionId = null;
    this.gameState = {
      ball: { x: 400, y: 300, vx: 3, vy: 2 },
      paddles: { p1: 250, p2: 250 },
      scores: { p1: 0, p2: 0 },
      started: false,
      finished: false,
    };
    this.lastUpdate = Date.now();
  }

  async fetch(request) {
    const url = new URL(request.url);
    
    if (url.pathname.endsWith('/info')) {
      return new Response(JSON.stringify({
        creatorName: this.creatorName,
        playerCount: this.players.size,
      }), { headers: { 'Content-Type': 'application/json' } });
    }

    if (url.pathname.endsWith('/init')) {
      const { sessionId } = await request.json();
      this.sessionId = sessionId;
      return new Response('OK');
    }

    const upgrade = request.headers.get('Upgrade');
    if (upgrade !== 'websocket') {
      return new Response('Expected WebSocket', { status: 426 });
    }

    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    const msg = JSON.parse(message);
    console.log('[DO] Received message:', msg, 'Current players:', this.players.size);

    if (msg.type === 'set_name') {
      // Check if this websocket already has a player assigned
      if (!this.players.has(ws)) {
        const playerId = this.players.size === 0 ? 'p1' : 'p2';
        console.log('[DO] Assigning player ID:', playerId, 'to', msg.name);
        this.players.set(ws, { id: playerId, name: msg.name });
        
        if (!this.creatorName) {
          this.creatorName = msg.name;
        }
      } else {
        console.log('[DO] WebSocket already has player assigned');
      }
      
      console.log('[DO] Broadcasting lobby with players:', this.getLobbyPlayers());
      this.broadcast({ type: 'lobby', players: this.getLobbyPlayers() });
    }

    if (msg.type === 'start' && this.players.size === 2 && !this.gameState.started) {
      this.gameState.started = true;
      this.broadcast({ type: 'start' });
      this.startGameLoop();
    }

    if (msg.type === 'move' && this.gameState.started && !this.gameState.finished) {
      const player = this.players.get(ws);
      if (player) {
        this.gameState.paddles[player.id] = Math.max(0, Math.min(500, msg.y));
      }
    }
  }

  webSocketClose(ws) {
    console.log('[DO] WebSocket closed, players before:', this.players.size);
    this.players.delete(ws);
    console.log('[DO] Players after delete:', this.players.size);
    this.broadcast({ type: 'lobby', players: this.getLobbyPlayers() });
  }

  getLobbyPlayers() {
    return Array.from(this.players.values()).map(p => ({ id: p.id, name: p.name }));
  }

  broadcast(msg) {
    const data = JSON.stringify(msg);
    this.ctx.getWebSockets().forEach(ws => ws.send(data));
  }

  startGameLoop() {
    const tick = async () => {
      if (this.gameState.finished || this.players.size < 2) return;

      const now = Date.now();
      const dt = (now - this.lastUpdate) / 16.67;
      this.lastUpdate = now;

      this.gameState.ball.x += this.gameState.ball.vx * dt;
      this.gameState.ball.y += this.gameState.ball.vy * dt;

      if (this.gameState.ball.y <= 10 || this.gameState.ball.y >= 590) {
        this.gameState.ball.vy *= -1;
      }

      if (this.gameState.ball.x <= 30 && Math.abs(this.gameState.ball.y - this.gameState.paddles.p1) < 50) {
        this.gameState.ball.vx = Math.abs(this.gameState.ball.vx);
      }
      if (this.gameState.ball.x >= 770 && Math.abs(this.gameState.ball.y - this.gameState.paddles.p2) < 50) {
        this.gameState.ball.vx = -Math.abs(this.gameState.ball.vx);
      }

      if (this.gameState.ball.x < 0) {
        this.gameState.scores.p2++;
        this.resetBall();
      }
      if (this.gameState.ball.x > 800) {
        this.gameState.scores.p1++;
        this.resetBall();
      }

      if (this.gameState.scores.p1 >= 5 || this.gameState.scores.p2 >= 5) {
        this.gameState.finished = true;
        const winner = this.gameState.scores.p1 >= 5 ? 'p1' : 'p2';
        this.broadcast({ type: 'game_over', winner, scores: this.gameState.scores });
        
        // Delete session from database
        if (this.sessionId && this.env.DB) {
          await this.env.DB.prepare('DELETE FROM pong_sessions WHERE session_id = ?')
            .bind(this.sessionId).run();
          console.log('[DO] Deleted session from database:', this.sessionId);
        }
        
        setTimeout(() => this.ctx.getWebSockets().forEach(ws => ws.close()), 5000);
        return;
      }

      this.broadcast({ type: 'state', ...this.gameState });
      setTimeout(tick, 16);
    };
    tick();
  }

  resetBall() {
    this.gameState.ball = { x: 400, y: 300, vx: 3 * (Math.random() > 0.5 ? 1 : -1), vy: 2 * (Math.random() > 0.5 ? 1 : -1) };
  }
}
