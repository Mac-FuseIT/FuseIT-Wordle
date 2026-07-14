import { DurableObject } from 'cloudflare:workers';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const RED_NUMBERS = new Set([1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]);
const BETTING_DURATION = 20000;  // 20 seconds
const SPINNING_DURATION = 5000;  // 5 seconds
const RESULT_DURATION = 5000;    // 5 seconds

function getColor(number) {
  if (number === 0) return 'green';
  return RED_NUMBERS.has(number) ? 'red' : 'black';
}

// ---------------------------------------------------------------------------
// Date helper — same weekend-mapping logic as blackjack (Sat→Fri, Sun→Fri)
// ---------------------------------------------------------------------------

function getToday() {
  const date = new Date();
  const day = date.getUTCDay();
  if (day === 0) date.setUTCDate(date.getUTCDate() - 2); // Sun → Fri
  else if (day === 6) date.setUTCDate(date.getUTCDate() - 1); // Sat → Fri
  return date.toISOString().split('T')[0];
}

// ---------------------------------------------------------------------------
// Default state factory
// ---------------------------------------------------------------------------

function defaultState() {
  return {
    phase: 'idle',
    players: [],
    roundNumber: 0,
    winningNumber: null,
    winningColor: null,
    history: [],
    phaseEndTime: null,
  };
}

// ---------------------------------------------------------------------------
// Durable Object
// ---------------------------------------------------------------------------

export class RouletteTable extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
  }

  // -------------------------------------------------------------------------
  // Storage helpers
  // -------------------------------------------------------------------------

  async getState() {
    return (await this.ctx.storage.get('state')) || defaultState();
  }

  async saveState(state) {
    await this.ctx.storage.put('state', state);
  }

  // -------------------------------------------------------------------------
  // Fetch handler — WebSocket upgrade or HTTP status
  // -------------------------------------------------------------------------

  async fetch(request) {
    const url = new URL(request.url);

    // HTTP status endpoint (lobby polling)
    if (url.pathname === '/status') {
      const state = await this.getState();
      return new Response(
        JSON.stringify({
          players: state.players.map(p => ({ userId: p.userId, name: p.name })),
          phase: state.phase,
          roundNumber: state.roundNumber,
        }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    }

    // WebSocket upgrade (game connection)
    const upgradeHeader = request.headers.get('Upgrade');
    if (upgradeHeader && upgradeHeader.toLowerCase() === 'websocket') {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server);
      return new Response(null, { status: 101, webSocket: client });
    }

    return new Response('Not found', { status: 404 });
  }

  // -------------------------------------------------------------------------
  // Alarm — game loop driver
  // -------------------------------------------------------------------------

  async alarm() {
    const state = await this.getState();
    switch (state.phase) {
      case 'betting':
        await this.transitionToSpinning(state);
        break;
      case 'spinning':
        await this.transitionToResult(state);
        break;
      case 'result':
        await this.transitionToBetting(state);
        break;
      // 'idle' — alarm should not fire when idle, but guard anyway
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // WebSocket message handler
  // -------------------------------------------------------------------------

  async webSocketMessage(ws, msg) {
    let data;
    try { data = JSON.parse(msg); } catch (_) { return; }

    const state = await this.getState();

    switch (data.type) {
      case 'join':       await this._handleJoin(ws, data, state); break;
      case 'place_bet':  await this._handlePlaceBet(ws, data, state); break;
      case 'clear_bets': await this._handleClearBets(ws, data, state); break;
      case 'leave':      await this._handleLeave(ws, data, state); break;
      default: break;
    }
  }

  // -------------------------------------------------------------------------
  // WebSocket close
  // -------------------------------------------------------------------------

  async webSocketClose(ws) {
    const att = ws.deserializeAttachment();
    if (!att) return;
    const { userId, name } = att;

    const state = await this.getState();
    const idx = state.players.findIndex(p => p.userId === userId);
    if (idx === -1) return;

    state.players.splice(idx, 1);
    this.broadcast({ type: 'player_left', userId, name });

    if (state.players.length === 0) {
      state.phase = 'idle';
      await this.ctx.storage.deleteAlarm();
    }

    await this.saveState(state);
  }

  webSocketError(ws) { this.webSocketClose(ws); }

  // -------------------------------------------------------------------------
  // Handler: join
  // -------------------------------------------------------------------------

  async _handleJoin(ws, data, state) {
    const { userId, name } = data;

    // Reconnect — player already in state
    const existing = state.players.find(p => p.userId === userId);
    if (existing) {
      ws.serializeAttachment({ userId, name: existing.name });
      const gameState = await this.getGameState(userId, state);
      try { ws.send(JSON.stringify(gameState)); } catch (_) {}
      return;
    }

    // New player — check cashout status
    const today = getToday();
    let spectator = false;
    try {
      const cashoutRow = await this.env.DB.prepare(
        'SELECT id FROM blackjack_results WHERE user_id = ? AND date = ?'
      ).bind(userId, today).first();
      if (cashoutRow) spectator = true;
    } catch (_) {}

    // Read balance from blackjack_sessions (or create default)
    let balance = 100;
    try {
      const row = await this.env.DB.prepare(
        'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
      ).bind(userId, today).first();
      if (row) {
        const session = JSON.parse(row.session_state);
        balance = session.balance;
      } else {
        // Create default session (same defaultSession as blackjack)
        const defaultSess = {
          balance: 100,
          deck: [],
          playerHand: [],
          dealerHand: [],
          currentBet: 0,
          handsPlayed: 0,
          handsWon: 0,
          blackjacks: 0,
          gameOver: false,
        };
        await this.env.DB.prepare(
          'INSERT INTO blackjack_sessions (user_id, date, session_state) VALUES (?, ?, ?)'
        ).bind(userId, today, JSON.stringify(defaultSess)).run();
        balance = 100;
      }
    } catch (_) {}

    // Add player to state
    state.players.push({ userId, name, bets: [], spectator, balance });

    // Tag the websocket with this player's identity
    ws.serializeAttachment({ userId, name });

    // Send full game state to this player
    const gameState = await this.getGameState(userId, state);
    try { ws.send(JSON.stringify(gameState)); } catch (_) {}

    // Broadcast to all other players
    this.broadcast({ type: 'player_joined', userId, name }, ws);

    // If table was idle, start the game loop now (first player)
    if (state.phase === 'idle') {
      await this.transitionToBetting(state);
      return; // transitionToBetting saves state
    }

    await this.saveState(state);
  }

  // -------------------------------------------------------------------------
  // Handler: place_bet
  // -------------------------------------------------------------------------

  async _handlePlaceBet(ws, data, state) {
    const att = ws.deserializeAttachment();
    if (!att) return;
    const { userId, name } = att;

    if (state.phase !== 'betting') {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Not in betting phase' })); } catch (_) {}
      return;
    }

    const player = state.players.find(p => p.userId === userId);
    if (!player) return;

    if (player.spectator) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Already cashed out today — spectator mode only' })); } catch (_) {}
      return;
    }

    const { betType, betValue, amount } = data;
    const validBetTypes = ['straight', 'red', 'black', 'odd', 'even', 'high', 'low'];
    if (!validBetTypes.includes(betType)) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Invalid bet type' })); } catch (_) {}
      return;
    }

    const betAmount = parseInt(amount);
    if (!betAmount || betAmount < 1) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Bet amount must be at least 1' })); } catch (_) {}
      return;
    }

    // Read fresh balance from D1
    const today = getToday();
    let session;
    try {
      const row = await this.env.DB.prepare(
        'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
      ).bind(userId, today).first();
      if (!row) {
        try { ws.send(JSON.stringify({ type: 'error', message: 'No session found' })); } catch (_) {}
        return;
      }
      session = JSON.parse(row.session_state);
    } catch (e) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Failed to read session' })); } catch (_) {}
      return;
    }

    if (session.balance < betAmount) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Insufficient balance' })); } catch (_) {}
      return;
    }

    // Deduct bet immediately from D1
    session.balance -= betAmount;
    try {
      await this.env.DB.prepare(
        'UPDATE blackjack_sessions SET session_state = ? WHERE user_id = ? AND date = ?'
      ).bind(JSON.stringify(session), userId, today).run();
    } catch (e) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Failed to place bet' })); } catch (_) {}
      return;
    }

    // Record bet in DO state
    player.bets.push({ betType, betValue: betValue ?? null, amount: betAmount });
    player.balance = session.balance;

    await this.saveState(state);
    this.broadcast({ type: 'bet_placed', userId, name, betType, betValue: betValue ?? null, amount: betAmount });
  }

  // -------------------------------------------------------------------------
  // Handler: clear_bets
  // -------------------------------------------------------------------------

  async _handleClearBets(ws, data, state) {
    const att = ws.deserializeAttachment();
    if (!att) return;
    const { userId } = att;

    if (state.phase !== 'betting') {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Not in betting phase' })); } catch (_) {}
      return;
    }

    const player = state.players.find(p => p.userId === userId);
    if (!player || player.bets.length === 0) return;

    // Refund all bets back to D1
    const today = getToday();
    const totalRefund = player.bets.reduce((sum, b) => sum + b.amount, 0);

    try {
      const row = await this.env.DB.prepare(
        'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
      ).bind(userId, today).first();
      if (row) {
        const session = JSON.parse(row.session_state);
        session.balance += totalRefund;
        await this.env.DB.prepare(
          'UPDATE blackjack_sessions SET session_state = ? WHERE user_id = ? AND date = ?'
        ).bind(JSON.stringify(session), userId, today).run();
        player.balance = session.balance;
      }
    } catch (_) {}

    player.bets = [];

    await this.saveState(state);
    this.broadcast({ type: 'bets_cleared', userId });
  }

  // -------------------------------------------------------------------------
  // Handler: leave
  // -------------------------------------------------------------------------

  async _handleLeave(ws, data, state) {
    const att = ws.deserializeAttachment();
    if (!att) return;
    const { userId, name } = att;

    const idx = state.players.findIndex(p => p.userId === userId);
    if (idx === -1) return;

    state.players.splice(idx, 1);
    this.broadcast({ type: 'player_left', userId, name });

    if (state.players.length === 0) {
      state.phase = 'idle';
      await this.ctx.storage.deleteAlarm();
    }

    await this.saveState(state);
  }

  // -------------------------------------------------------------------------
  // Phase transitions
  // -------------------------------------------------------------------------

  async transitionToBetting(state) {
    state.phase = 'betting';
    state.roundNumber += 1;
    // Clear all bets for the new round
    for (const p of state.players) {
      p.bets = [];
    }
    state.phaseEndTime = Date.now() + BETTING_DURATION;
    await this.ctx.storage.setAlarm(Date.now() + BETTING_DURATION);
    await this.saveState(state);
    this.broadcast({ type: 'betting', timeRemaining: BETTING_DURATION, roundNumber: state.roundNumber });
  }

  async transitionToSpinning(state) {
    state.phase = 'spinning';
    const winningNumber = Math.floor(Math.random() * 37); // 0–36
    const winningColor = getColor(winningNumber);
    state.winningNumber = winningNumber;
    state.winningColor = winningColor;
    state.phaseEndTime = Date.now() + SPINNING_DURATION;

    // Build totalBets map: { userId: totalAmount }
    const totalBets = {};
    for (const p of state.players) {
      const total = p.bets.reduce((sum, b) => sum + b.amount, 0);
      if (total > 0) totalBets[p.userId] = total;
    }

    await this.ctx.storage.setAlarm(Date.now() + SPINNING_DURATION);
    await this.saveState(state);
    this.broadcast({ type: 'spinning', winningNumber, winningColor, totalBets });
  }

  async transitionToResult(state) {
    state.phase = 'result';
    const { winningNumber, winningColor } = state;
    const today = getToday();
    const payouts = [];

    for (const player of state.players) {
      let totalWon = 0;
      let totalWagered = 0;

      for (const bet of player.bets) {
        totalWagered += bet.amount;
        let payout = 0;

        switch (bet.betType) {
          case 'straight':
            if (bet.betValue === winningNumber) payout = bet.amount * 35 + bet.amount;
            break;
          case 'red':
            if (winningColor === 'red') payout = bet.amount * 2;
            break;
          case 'black':
            if (winningColor === 'black') payout = bet.amount * 2;
            break;
          case 'odd':
            if (winningNumber > 0 && winningNumber % 2 === 1) payout = bet.amount * 2;
            break;
          case 'even':
            if (winningNumber > 0 && winningNumber % 2 === 0) payout = bet.amount * 2;
            break;
          case 'high':
            if (winningNumber >= 19) payout = bet.amount * 2;
            break;
          case 'low':
            if (winningNumber >= 1 && winningNumber <= 18) payout = bet.amount * 2;
            break;
          default:
            break;
        }

        totalWon += payout;
      }

      const netProfit = totalWon - totalWagered;

      // Credit winnings to D1 (only if player won something)
      let newBalance = player.balance;
      if (totalWon > 0) {
        try {
          const row = await this.env.DB.prepare(
            'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
          ).bind(player.userId, today).first();
          if (row) {
            const session = JSON.parse(row.session_state);
            session.balance += totalWon;
            await this.env.DB.prepare(
              'UPDATE blackjack_sessions SET session_state = ? WHERE user_id = ? AND date = ?'
            ).bind(JSON.stringify(session), player.userId, today).run();
            newBalance = session.balance;
            player.balance = newBalance;
          }
        } catch (_) {}
      }

      // Upsert roulette_results (increment stats)
      if (totalWagered > 0) {
        try {
          await this.env.DB.prepare(`
            INSERT INTO roulette_results (user_id, date, spins_played, total_wagered, total_won, net_profit, updated_at)
            VALUES (?, ?, 1, ?, ?, ?, datetime('now'))
            ON CONFLICT(user_id, date) DO UPDATE SET
              spins_played = spins_played + 1,
              total_wagered = total_wagered + excluded.total_wagered,
              total_won = total_won + excluded.total_won,
              net_profit = net_profit + excluded.net_profit,
              updated_at = datetime('now')
          `).bind(player.userId, today, totalWagered, totalWon, netProfit).run();
        } catch (_) {}
      }

      payouts.push({ userId: player.userId, name: player.name, totalWon, netProfit, newBalance });
    }

    // Add winning number to history (keep last 10)
    state.history.push(winningNumber);
    if (state.history.length > 10) state.history = state.history.slice(-10);

    state.phaseEndTime = Date.now() + RESULT_DURATION;
    await this.ctx.storage.setAlarm(Date.now() + RESULT_DURATION);
    await this.saveState(state);
    this.broadcast({ type: 'result', winningNumber, winningColor, payouts });
  }

  // -------------------------------------------------------------------------
  // Game state snapshot (for join / reconnect)
  // -------------------------------------------------------------------------

  async getGameState(userId, state) {
    const player = state.players.find(p => p.userId === userId);

    // Read fresh balance for the joining player
    let yourBalance = player ? player.balance : 0;
    if (player) {
      const today = getToday();
      try {
        const row = await this.env.DB.prepare(
          'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
        ).bind(userId, today).first();
        if (row) {
          yourBalance = JSON.parse(row.session_state).balance;
          player.balance = yourBalance;
        }
      } catch (_) {}
    }

    return {
      type: 'game_state',
      phase: state.phase,
      timeRemaining: state.phaseEndTime ? Math.max(0, state.phaseEndTime - Date.now()) : 0,
      players: state.players.map(p => ({ userId: p.userId, name: p.name, bets: p.bets })),
      yourBalance,
      yourBets: player ? player.bets : [],
      lastResult: { winningNumber: state.winningNumber, color: state.winningColor },
      history: state.history,
      roundNumber: state.roundNumber,
    };
  }

  // -------------------------------------------------------------------------
  // Broadcast helpers
  // -------------------------------------------------------------------------

  /** Broadcast to all connected WebSockets, optionally excluding one. */
  broadcast(data, excludeWs = null) {
    const msg = JSON.stringify(data);
    this.ctx.getWebSockets().forEach(ws => {
      if (ws === excludeWs) return;
      try { ws.send(msg); } catch (_) {}
    });
  }
}

// ---------------------------------------------------------------------------
// Default export — routes /join and /status to the single DO instance
// ---------------------------------------------------------------------------

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/status') {
      const id = env.ROULETTE_TABLE.idFromName('roulette-main');
      const stub = env.ROULETTE_TABLE.get(id);
      return stub.fetch(request);
    }

    if (url.pathname === '/join') {
      const id = env.ROULETTE_TABLE.idFromName('roulette-main');
      const stub = env.ROULETTE_TABLE.get(id);
      return stub.fetch(request);
    }

    return new Response('Not found', { status: 404 });
  }
};
