import { DurableObject } from 'cloudflare:workers';

export class ChessGameSession extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
  }

  async getState() {
    return (await this.ctx.storage.get('state')) || {
      players: [],
      started: false,
      readyPlayers: [],
      moves: [],
      colorChoice: 'random',
      timeControl: 'unlimited',
      timers: { white: 0, black: 0 },
      lastMoveTime: null,
      sessionId: null,
    };
  }

  async saveState(state) {
    await this.ctx.storage.put('state', state);
  }

  async fetch(request) {
    const upgradeHeader = request.headers.get('Upgrade');
    if (!upgradeHeader || upgradeHeader !== 'websocket') {
      return new Response('Expected WebSocket', { status: 426 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, msg) {
    const data = JSON.parse(msg);
    const state = await this.getState();

    switch (data.type) {
      case 'join': {
        // First joiner sets config
        if (state.players.length === 0 && data.colorChoice) {
          state.colorChoice = data.colorChoice;
          state.timeControl = data.timeControl || 'unlimited';
          const timeMs = { '3min': 180000, '5min': 300000, '10min': 600000, 'unlimited': 0 };
          state.timers = { white: timeMs[state.timeControl] || 0, black: timeMs[state.timeControl] || 0 };
          state.sessionId = data.sessionId || '';
        }

        // Don't add duplicate players
        if (!state.players.find(p => p.id === data.userId)) {
          const num = state.players.length + 1;
          state.players.push({ id: data.userId, name: data.name, num });
        }

        // Clear disconnect state if this player is reconnecting
        if (state.disconnectedPlayer === data.userId) {
          state.disconnectedPlayer = null;
          state.disconnectTime = null;
          this.broadcast({ type: 'opponent_reconnected', userId: data.userId });
        }

        // Tag the websocket with the user ID for identification
        ws.serializeAttachment({ userId: data.userId, name: data.name });

        await this.saveState(state);
        this.broadcast({ type: 'players', players: this.getPlayerList(state) });

        // If game was already started (reconnect mid-game), send current state
        if (state.started) {
          try { ws.send(JSON.stringify({ type: 'start', colors: this.getPlayerList(state), timeControl: state.timeControl, timers: state.timers })); } catch(_) {}
          if (state.moves.length > 0) {
            try { ws.send(JSON.stringify({ type: 'sync', moves: state.moves, timers: state.timers })); } catch(_) {}
          }
        } else if (state.readyPlayers.length > 0) {
          try { ws.send(JSON.stringify({ type: 'ready_status', ready: state.readyPlayers })); } catch(_) {}
        }
        break;
      }
      case 'ready': {
        const att = ws.deserializeAttachment();
        if (att && !state.readyPlayers.includes(att.userId)) {
          state.readyPlayers.push(att.userId);
          await this.saveState(state);
          this.broadcast({ type: 'ready_status', ready: state.readyPlayers });
          if (state.readyPlayers.length === 2 && state.players.length === 2) {
            this.startCountdown(state);
          }
        }
        break;
      }
      case 'move': {
        if (!state.started) return;
        const att = ws.deserializeAttachment();
        if (!att) return;

        const isWhiteTurn = state.moves.length % 2 === 0;
        const playerColor = this.getPlayerColor(state, att.userId);
        if ((isWhiteTurn && playerColor !== 'white') || (!isWhiteTurn && playerColor !== 'black')) return;

        // Timer logic
        if (state.timeControl !== 'unlimited' && state.lastMoveTime) {
          const elapsed = Date.now() - state.lastMoveTime;
          if (isWhiteTurn) state.timers.white -= elapsed;
          else state.timers.black -= elapsed;

          if (state.timers.white <= 0 || state.timers.black <= 0) {
            const loser = state.timers.white <= 0 ? 'white' : 'black';
            await this.endGame(state, loser === 'white' ? 'black' : 'white', 'timeout');
            return;
          }
        }
        state.lastMoveTime = Date.now();
        state.moves.push(data.move);
        await this.saveState(state);

        this.broadcast({ type: 'move', move: data.move, moves: state.moves, timers: state.timers });

        if (data.gameOver) {
          await this.endGame(state, data.winner, data.reason || 'checkmate');
        }
        break;
      }
    }
  }

  async webSocketClose(ws) {
    const state = await this.getState();
    const att = ws.deserializeAttachment();
    if (!state.started || !att) return;

    // Unlimited games: never forfeit on disconnect, players can return anytime
    if (state.timeControl === 'unlimited') return;

    // Timed games: 30s grace period
    const disconnectedId = att.userId;
    state.disconnectedPlayer = disconnectedId;
    state.disconnectTime = Date.now();
    await this.saveState(state);

    this.broadcast({ type: 'opponent_disconnected', userId: disconnectedId });

    setTimeout(async () => {
      const s = await this.getState();
      if (s.disconnectedPlayer === disconnectedId) {
        const otherPlayer = s.players.find(p => p.id !== disconnectedId);
        if (otherPlayer) {
          await this.endGame(s, this.getPlayerColor(s, otherPlayer.id), 'disconnect');
        }
      }
    }, 30000);
  }

  webSocketError(ws) { this.webSocketClose(ws); }

  getPlayerList(state) {
    return state.players.map(p => ({ id: p.id, name: p.name, num: p.num, color: this.getPlayerColor(state, p.id) }));
  }

  getPlayerColor(state, userId) {
    const player = state.players.find(p => p.id === userId);
    if (!player) return 'white';
    if (state.colorChoice === 'random') {
      const seed = (state.sessionId || '').charCodeAt(0) || 0;
      return player.num === 1 ? (seed % 2 === 0 ? 'white' : 'black') : (seed % 2 === 0 ? 'black' : 'white');
    }
    return player.num === 1 ? state.colorChoice : (state.colorChoice === 'white' ? 'black' : 'white');
  }

  startCountdown(state) {
    this.broadcast({ type: 'countdown', seconds: 10 });
    setTimeout(async () => {
      const s = await this.getState();
      s.started = true;
      s.lastMoveTime = Date.now();
      await this.saveState(s);
      this.broadcast({ type: 'start', colors: this.getPlayerList(s), timeControl: s.timeControl, timers: s.timers });
    }, 10000);
  }

  async endGame(state, winnerColor, reason) {
    state.started = false;
    await this.saveState(state);

    const winner = state.players.find(p => this.getPlayerColor(state, p.id) === winnerColor);
    const loser = state.players.find(p => this.getPlayerColor(state, p.id) !== winnerColor);

    this.broadcast({ type: 'game_over', winner: winnerColor, reason, moves: state.moves.length });

    if (winner && loser) {
      try {
        await this.env.DB.prepare(
          `INSERT INTO chess_pvp_results (winner_id, loser_id, winner_name, loser_name, moves, time_control, played_at) VALUES (?, ?, ?, ?, ?, ?, ?)`
        ).bind(winner.id, loser.id, winner.name, loser.name, Math.ceil(state.moves.length / 2), state.timeControl, new Date().toISOString()).run();
      } catch (_) {}
      try {
        await this.env.DB.prepare('DELETE FROM chess_pvp_challenges WHERE session_id = ?').bind(state.sessionId).run();
      } catch (_) {}
    }

    // Clean up after 5s
    setTimeout(() => {
      this.ctx.getWebSockets().forEach(ws => { try { ws.close(1000, 'Game over'); } catch(_) {} });
    }, 5000);
  }

  broadcast(data) {
    const msg = JSON.stringify(data);
    this.ctx.getWebSockets().forEach(ws => { try { ws.send(msg); } catch (_) {} });
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const joinMatch = url.pathname.match(/^\/join\/(.+)$/);
    if (joinMatch) {
      const sessionId = joinMatch[1];
      const id = env.CHESS_GAME.idFromName(sessionId);
      const stub = env.CHESS_GAME.get(id);
      return stub.fetch(request);
    }
    return new Response('Not found', { status: 404 });
  }
};
