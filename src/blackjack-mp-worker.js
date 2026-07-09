import { DurableObject } from 'cloudflare:workers';

// ---------------------------------------------------------------------------
// Game logic (mirrors functions/api/blackjack/bet.js)
// ---------------------------------------------------------------------------

function createDeck() {
  const suits = ['hearts', 'diamonds', 'clubs', 'spades'];
  const ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
  const deck = [];
  for (const suit of suits) {
    for (const rank of ranks) {
      deck.push({ suit, rank });
    }
  }
  // Fisher-Yates shuffle
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

function cardValue(card) {
  if (['J', 'Q', 'K'].includes(card.rank)) return 10;
  if (card.rank === 'A') return 11;
  return parseInt(card.rank);
}

function handValue(hand) {
  let total = hand.reduce((sum, card) => sum + cardValue(card), 0);
  let aces = hand.filter(c => c.rank === 'A').length;
  while (total > 21 && aces > 0) {
    total -= 10;
    aces--;
  }
  return total;
}

function isBlackjack(hand) {
  return hand.length === 2 && handValue(hand) === 21;
}

/**
 * Draw a card from the deck. If the deck is empty, reshuffle a fresh deck
 * excluding any cards currently in play (inPlayCards).
 */
function drawCard(deck, inPlayCards = []) {
  if (deck.length < 1) {
    const fresh = createDeck();
    const reshuffled = fresh.filter(
      card => !inPlayCards.some(p => p.suit === card.suit && p.rank === card.rank)
    );
    deck.push(...reshuffled);
  }
  return deck.pop();
}

/** Returns YYYY-MM-DD for today in UTC (same logic as src/db.js getToday).
 *  Sat → Fri, Sun → Fri so DO reads/writes the same blackjack_sessions row. */
function getToday() {
  const date = new Date();
  const day = date.getUTCDay();
  if (day === 0) date.setUTCDate(date.getUTCDate() - 2); // Sun → Fri
  else if (day === 6) date.setUTCDate(date.getUTCDate() - 1); // Sat → Fri
  return date.toISOString().split('T')[0];
}

/** Build the default empty session for a new blackjack_sessions row. */
function defaultSession() {
  return {
    balance: 100,
    deck: createDeck(),
    playerHand: [],
    dealerHand: [],
    currentBet: 0,
    handsPlayed: 0,
    handsWon: 0,
    blackjacks: 0,
    gameOver: false,
  };
}

// ---------------------------------------------------------------------------
// Durable Object
// ---------------------------------------------------------------------------

export class BlackjackMultiplayerSession extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
  }

  // -------------------------------------------------------------------------
  // Storage helpers
  // -------------------------------------------------------------------------

  async getState() {
    return (await this.ctx.storage.get('state')) || {
      gameId: null,
      phase: 'waiting',
      players: [],
      dealer: { hand: [], value: 0 },
      deck: [],
      currentTurn: 0,
      creatorId: null,
      betsPlaced: 0,
      activeBettors: 0,
    };
  }

  async saveState(state) {
    await this.ctx.storage.put('state', state);
  }

  // -------------------------------------------------------------------------
  // WebSocket upgrade
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // WebSocket message handler
  // -------------------------------------------------------------------------

  async webSocketMessage(ws, msg) {
    let data;
    try { data = JSON.parse(msg); } catch (_) { return; }

    const state = await this.getState();
    const att = ws.deserializeAttachment() || {};

    switch (data.type) {
      case 'join':      await this._handleJoin(ws, data, state); break;
      case 'start_round': await this._handleStartRound(ws, data, state, att); break;
      case 'place_bet': await this._handlePlaceBet(ws, data, state, att); break;
      case 'hit':       await this._handleHit(ws, data, state, att); break;
      case 'stand':     await this._handleStand(ws, data, state, att); break;
      case 'double':    await this._handleDouble(ws, data, state, att); break;
      case 'leave':     await this._handleLeave(ws, data, state, att); break;
      default: break;
    }
  }

  // -------------------------------------------------------------------------
  // Handler: join
  // -------------------------------------------------------------------------

  async _handleJoin(ws, data, state) {
    const { userId, name, gameId } = data;

    const existing = state.players.find(p => p.userId === userId);

    if (existing) {
      // Reconnect — re-tag the new websocket
      ws.serializeAttachment({ userId, name: existing.name });
      this.broadcast({ type: 'player_reconnected', userId, name: existing.name });
      try { ws.send(JSON.stringify({ type: 'game_state', ...this.getGameStateFor(userId, state) })); } catch (_) {}
      return;
    }

    // New player checks
    if (state.phase !== 'waiting') {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Round already in progress' })); } catch (_) {}
      return;
    }
    if (state.players.length >= 4) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Game is full' })); } catch (_) {}
      return;
    }

    // First joiner becomes creator
    if (state.players.length === 0) {
      state.creatorId = userId;
      state.gameId = gameId || null;
    }

    state.players.push({
      userId,
      name,
      seatIndex: state.players.length,
      balance: 0,
      bet: 0,
      hand: [],
      value: 0,
      status: 'waiting',
      hasActed: false,
      pendingLeave: false,
    });

    // Fetch player's current balance from D1
    const today = getToday();
    try {
      const row = await this.env.DB.prepare(
        'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
      ).bind(userId, today).first();

      if (row) {
        const session = JSON.parse(row.session_state);
        state.players[state.players.length - 1].balance = session.balance;
      } else {
        // Create default session if none exists
        const session = defaultSession();
        await this.env.DB.prepare(
          'INSERT INTO blackjack_sessions (user_id, date, session_state) VALUES (?, ?, ?)'
        ).bind(userId, today, JSON.stringify(session)).run();
        state.players[state.players.length - 1].balance = session.balance;
      }
    } catch (_) {
      // If D1 read fails, default to 100
      state.players[state.players.length - 1].balance = 100;
    }

    ws.serializeAttachment({ userId, name });
    await this.saveState(state);

    this.broadcast({ type: 'player_joined', userId, name, seatIndex: state.players.length - 1 });
    try { ws.send(JSON.stringify({ type: 'game_state', ...this.getGameStateFor(userId, state) })); } catch (_) {}

    // Update D1 player count
    if (state.gameId) {
      try {
        await this.env.DB.prepare(
          'UPDATE blackjack_mp_games SET player_count = ? WHERE id = ?'
        ).bind(state.players.length, state.gameId).run();
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------------------
  // Handler: start_round
  // -------------------------------------------------------------------------

  async _handleStartRound(ws, data, state, att) {
    const { userId } = att;

    if (userId !== state.creatorId) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Only the creator can start the round' })); } catch (_) {}
      return;
    }
    if (state.phase !== 'waiting') {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Round already started' })); } catch (_) {}
      return;
    }
    if (state.players.length < 2) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Need at least 2 players' })); } catch (_) {}
      return;
    }

    state.phase = 'betting';
    state.betsPlaced = 0;
    state.activeBettors = state.players.length;
    state.dealer = { hand: [], value: 0 };

    for (const p of state.players) {
      p.bet = 0;
      p.hand = [];
      p.value = 0;
      p.status = 'betting';
      p.hasActed = false;
    }

    await this.saveState(state);
    this.broadcast({ type: 'betting_phase', timeout: 30 });

    // 30s betting timeout — auto-deal with whoever has bet
    setTimeout(async () => {
      const s = await this.getState();
      if (s.phase === 'betting') {
        await this.startDealing(s);
      }
    }, 30000);

    // Update D1
    if (state.gameId) {
      try {
        await this.env.DB.prepare(
          "UPDATE blackjack_mp_games SET status = 'playing' WHERE id = ?"
        ).bind(state.gameId).run();
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------------------
  // Handler: place_bet
  // -------------------------------------------------------------------------

  async _handlePlaceBet(ws, data, state, att) {
    const { userId } = att;
    const amount = parseInt(data.amount);

    if (state.phase !== 'betting') {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Not in betting phase' })); } catch (_) {}
      return;
    }

    const player = state.players.find(p => p.userId === userId);
    if (!player) return;

    if (player.status === 'bet_placed') {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Bet already placed' })); } catch (_) {}
      return;
    }

    if (!amount || amount < 1) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Invalid bet amount' })); } catch (_) {}
      return;
    }

    const today = getToday();

    // Check cashout
    try {
      const cashoutRow = await this.env.DB.prepare(
        'SELECT id FROM blackjack_results WHERE user_id = ? AND date = ?'
      ).bind(userId, today).first();
      if (cashoutRow) {
        try { ws.send(JSON.stringify({ type: 'error', message: 'Already cashed out today' })); } catch (_) {}
        return;
      }
    } catch (_) {}

    // Read or create session
    let session;
    try {
      const row = await this.env.DB.prepare(
        'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
      ).bind(userId, today).first();

      if (!row) {
        session = defaultSession();
        await this.env.DB.prepare(
          'INSERT INTO blackjack_sessions (user_id, date, session_state) VALUES (?, ?, ?)'
        ).bind(userId, today, JSON.stringify(session)).run();
      } else {
        session = JSON.parse(row.session_state);
      }
    } catch (e) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Failed to read session' })); } catch (_) {}
      return;
    }

    if (session.balance < amount) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Insufficient balance' })); } catch (_) {}
      return;
    }

    // Deduct immediately
    session.balance -= amount;
    try {
      await this.env.DB.prepare(
        'UPDATE blackjack_sessions SET session_state = ? WHERE user_id = ? AND date = ?'
      ).bind(JSON.stringify(session), userId, today).run();
    } catch (e) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Failed to update session' })); } catch (_) {}
      return;
    }

    player.bet = amount;
    player.balance = session.balance;
    player.status = 'bet_placed';
    state.betsPlaced++;

    await this.saveState(state);
    this.broadcast({ type: 'bet_placed', userId, name: player.name, amount });

    if (state.betsPlaced >= state.activeBettors) {
      await this.startDealing(state);
    }
  }

  // -------------------------------------------------------------------------
  // Handler: hit
  // -------------------------------------------------------------------------

  async _handleHit(ws, data, state, att) {
    const { userId } = att;
    if (state.phase !== 'playing') return;

    const player = state.players[state.currentTurn];
    if (!player || player.userId !== userId || player.status !== 'playing') return;

    const inPlay = this._allInPlayCards(state);
    const card = drawCard(state.deck, inPlay);
    player.hand.push(card);
    player.value = handValue(player.hand);
    player.hasActed = true;

    this.broadcast({ type: 'card_drawn', userId, card, hand: player.hand, value: player.value });

    if (player.value > 21) {
      player.status = 'bust';
      this.broadcast({ type: 'player_bust', userId, name: player.name, hand: player.hand, value: player.value });
      await this.saveState(state);
      await this.nextTurn(state);
    } else {
      await this.saveState(state);
    }
  }

  // -------------------------------------------------------------------------
  // Handler: stand
  // -------------------------------------------------------------------------

  async _handleStand(ws, data, state, att) {
    const { userId } = att;
    if (state.phase !== 'playing') return;

    const player = state.players[state.currentTurn];
    if (!player || player.userId !== userId) return;

    player.status = 'stood';
    this.broadcast({ type: 'player_stood', userId, name: player.name, hand: player.hand, value: player.value });

    await this.saveState(state);
    await this.nextTurn(state);
  }

  // -------------------------------------------------------------------------
  // Handler: double
  // -------------------------------------------------------------------------

  async _handleDouble(ws, data, state, att) {
    const { userId } = att;
    if (state.phase !== 'playing') return;

    const player = state.players[state.currentTurn];
    if (!player || player.userId !== userId || player.hasActed) return;

    const today = getToday();
    const additionalBet = player.bet;

    // Read current balance from D1
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

    if (session.balance < additionalBet) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Insufficient balance to double' })); } catch (_) {}
      return;
    }

    session.balance -= additionalBet;
    try {
      await this.env.DB.prepare(
        'UPDATE blackjack_sessions SET session_state = ? WHERE user_id = ? AND date = ?'
      ).bind(JSON.stringify(session), userId, today).run();
    } catch (e) {
      try { ws.send(JSON.stringify({ type: 'error', message: 'Failed to update session' })); } catch (_) {}
      return;
    }

    player.bet *= 2;
    player.balance = session.balance;

    const inPlay = this._allInPlayCards(state);
    const card = drawCard(state.deck, inPlay);
    player.hand.push(card);
    player.value = handValue(player.hand);
    player.hasActed = true;

    this.broadcast({
      type: 'player_doubled',
      userId,
      card,
      hand: player.hand,
      value: player.value,
      newBet: player.bet,
    });

    if (player.value > 21) {
      player.status = 'bust';
      this.broadcast({ type: 'player_bust', userId, name: player.name, hand: player.hand, value: player.value });
    } else {
      player.status = 'stood';
    }

    await this.saveState(state);
    await this.nextTurn(state);
  }

  // -------------------------------------------------------------------------
  // Handler: leave
  // -------------------------------------------------------------------------

  async _handleLeave(ws, data, state, att) {
    const { userId } = att;
    const player = state.players.find(p => p.userId === userId);
    if (!player) return;

    const activePhases = ['betting', 'playing', 'dealer_turn'];
    const inActiveRound = activePhases.includes(state.phase);

    if (inActiveRound) {
      // Don't remove mid-round — mark for removal; auto-stand if hand in progress
      player.pendingLeave = true;
      if (player.status === 'playing') {
        player.status = 'stood';
        // If it's their turn, advance
        if (state.players[state.currentTurn]?.userId === userId && state.phase === 'playing') {
          this.broadcast({ type: 'player_stood', userId, name: player.name, hand: player.hand, value: player.value });
          await this.saveState(state);
          await this.nextTurn(state);
          return;
        }
      }
    } else {
      // Safe to remove immediately
      const idx = state.players.findIndex(p => p.userId === userId);
      state.players.splice(idx, 1);
      // Re-index seatIndex
      state.players.forEach((p, i) => { p.seatIndex = i; });

      // Reassign creator if needed
      if (state.creatorId === userId && state.players.length > 0) {
        state.creatorId = state.players[0].userId;
      }
    }

    this.broadcast({ type: 'player_left', userId, name: player.name });

    // If nobody left, close up
    if (state.players.filter(p => !p.pendingLeave).length === 0) {
      if (state.gameId) {
        try {
          await this.env.DB.prepare(
            "UPDATE blackjack_mp_games SET status = 'finished' WHERE id = ?"
          ).bind(state.gameId).run();
        } catch (_) {}
      }
      this.ctx.getWebSockets().forEach(s => { try { s.close(1000, 'Game over'); } catch (_) {} });
    }

    await this.saveState(state);

    // Update D1 player count (active players only, excluding pending-leave)
    if (state.gameId) {
      try {
        const activeCount = state.players.filter(p => !p.pendingLeave).length;
        await this.env.DB.prepare(
          'UPDATE blackjack_mp_games SET player_count = ? WHERE id = ?'
        ).bind(activeCount, state.gameId).run();
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------------------
  // Helper: startDealing
  // -------------------------------------------------------------------------

  async startDealing(state) {
    const bettingPlayers = state.players.filter(p => p.status === 'bet_placed');

    if (bettingPlayers.length === 0) {
      // Nobody bet — go back to waiting
      state.phase = 'waiting';
      await this.saveState(state);
      this.broadcast({ type: 'game_state', ...this.getGameStateFor(null, state) });
      return;
    }

    // Ensure deck has enough cards
    const needed = bettingPlayers.length * 2 + 2 + 10;
    if (state.deck.length < needed) {
      state.deck = createDeck();
    }

    // Deal 2 cards to each betting player and 2 to dealer
    state.dealer.hand = [];
    for (const p of bettingPlayers) {
      p.hand = [];
    }

    for (let i = 0; i < 2; i++) {
      for (const p of bettingPlayers) {
        const inPlay = this._allInPlayCards(state);
        const card = drawCard(state.deck, inPlay);
        p.hand.push(card);
      }
      const inPlay = this._allInPlayCards(state);
      const dealerCard = drawCard(state.deck, inPlay);
      state.dealer.hand.push(dealerCard);
    }

    // Calculate values
    for (const p of bettingPlayers) {
      p.value = handValue(p.hand);
    }
    state.dealer.value = handValue(state.dealer.hand);

    const dealerBJ = isBlackjack(state.dealer.hand);

    // Mark blackjacks
    for (const p of bettingPlayers) {
      if (isBlackjack(p.hand)) {
        p.status = 'done';   // resolved at end
      } else if (dealerBJ) {
        p.status = 'done';   // immediate resolution
      } else {
        p.status = 'playing';
      }
    }

    // Players not in bettingPlayers keep their current status (waiting / pendingLeave etc.)
    state.phase = 'playing';

    const firstPlaying = bettingPlayers.find(p => p.status === 'playing');
    state.currentTurn = firstPlaying ? state.players.indexOf(firstPlaying) : -1;

    // Broadcast cards_dealt — hide dealer hole card
    this.broadcast({
      type: 'cards_dealt',
      players: bettingPlayers.map(p => ({ userId: p.userId, hand: p.hand, value: p.value })),
      dealer: {
        hand: [state.dealer.hand[0], { suit: 'hidden', rank: 'hidden' }],
        value: cardValue(state.dealer.hand[0]),
      },
    });

    await this.saveState(state);

    if (!firstPlaying) {
      // All players are 'done' (all BJ or dealer BJ)
      await this.dealerTurn(state);
      return;
    }

    this.broadcast({
      type: 'turn_start',
      userId: firstPlaying.userId,
      name: firstPlaying.name,
      canDouble: true,
    });

    // 30s auto-stand timeout for first player
    this._setTurnTimeout(firstPlaying.userId, 30000);
  }

  // -------------------------------------------------------------------------
  // Helper: nextTurn
  // -------------------------------------------------------------------------

  async nextTurn(state) {
    // Find next player after currentTurn with status 'playing'
    const total = state.players.length;
    let next = null;

    for (let offset = 1; offset <= total; offset++) {
      const idx = (state.currentTurn + offset) % total;
      if (state.players[idx].status === 'playing') {
        next = state.players[idx];
        state.currentTurn = idx;
        break;
      }
    }

    if (next) {
      await this.saveState(state);
      this.broadcast({
        type: 'turn_start',
        userId: next.userId,
        name: next.name,
        canDouble: !next.hasActed,
      });
      this._setTurnTimeout(next.userId, 30000);
    } else {
      await this.saveState(state);
      await this.dealerTurn(state);
    }
  }

  // -------------------------------------------------------------------------
  // Helper: dealerTurn
  // -------------------------------------------------------------------------

  async dealerTurn(state) {
    state.phase = 'dealer_turn';

    // Draw until 17+
    while (handValue(state.dealer.hand) < 17) {
      const inPlay = this._allInPlayCards(state);
      const card = drawCard(state.deck, inPlay);
      state.dealer.hand.push(card);
    }
    state.dealer.value = handValue(state.dealer.hand);

    this.broadcast({
      type: 'dealer_turn',
      cards: state.dealer.hand,
      finalHand: state.dealer.hand,
      finalValue: state.dealer.value,
    });

    await this.saveState(state);
    await this.resolveRound(state);
  }

  // -------------------------------------------------------------------------
  // Helper: resolveRound
  // -------------------------------------------------------------------------

  async resolveRound(state) {
    state.phase = 'round_over';
    const today = getToday();
    const dealerVal = state.dealer.value;
    const dealerBusted = dealerVal > 21;
    const results = [];

    const activePlayers = state.players.filter(p =>
      ['stood', 'bust', 'done'].includes(p.status)
    );

    for (const player of activePlayers) {
      let outcome;
      let payout;

      if (player.status === 'bust') {
        outcome = 'lose';
        payout = 0;
      } else if (isBlackjack(player.hand)) {
        outcome = 'blackjack';
        payout = player.bet + Math.floor(player.bet * 1.5);
      } else if (dealerBusted) {
        outcome = 'win';
        payout = player.bet * 2;
      } else if (player.value > dealerVal) {
        outcome = 'win';
        payout = player.bet * 2;
      } else if (player.value === dealerVal) {
        outcome = 'push';
        payout = player.bet;
      } else {
        outcome = 'lose';
        payout = 0;
      }

      const newBalance = player.balance + payout;
      player.balance = newBalance;

      // Write back to D1
      try {
        const row = await this.env.DB.prepare(
          'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
        ).bind(player.userId, today).first();

        if (row) {
          const session = JSON.parse(row.session_state);
          session.balance = newBalance;
          session.handsPlayed = (session.handsPlayed || 0) + 1;
          if (outcome === 'win' || outcome === 'blackjack') {
            session.handsWon = (session.handsWon || 0) + 1;
          }
          if (outcome === 'blackjack') {
            session.blackjacks = (session.blackjacks || 0) + 1;
          }
          await this.env.DB.prepare(
            'UPDATE blackjack_sessions SET session_state = ? WHERE user_id = ? AND date = ?'
          ).bind(JSON.stringify(session), player.userId, today).run();
        }
      } catch (_) {}

      results.push({
        userId: player.userId,
        name: player.name,
        outcome,
        payout,
        newBalance,
      });
    }

    this.broadcast({
      type: 'round_result',
      results,
      dealerHand: state.dealer.hand,
      dealerValue: dealerVal,
    });

    // Update D1 game status back to waiting
    if (state.gameId) {
      try {
        await this.env.DB.prepare(
          "UPDATE blackjack_mp_games SET status = 'waiting' WHERE id = ?"
        ).bind(state.gameId).run();
      } catch (_) {}
    }

    await this.saveState(state);

    // After 5s reset to waiting, remove pending leavers
    setTimeout(async () => {
      const s = await this.getState();
      s.phase = 'waiting';
      s.players = s.players.filter(p => !p.pendingLeave);
      s.players.forEach((p, i) => { p.seatIndex = i; });
      // Reassign creator if original left
      if (s.players.length > 0 && !s.players.find(p => p.userId === s.creatorId)) {
        s.creatorId = s.players[0].userId;
      }
      await this.saveState(s);
      this.broadcast({ type: 'game_state', ...this.getGameStateFor(null, s) });
    }, 5000);
  }

  // -------------------------------------------------------------------------
  // WebSocket close / error
  // -------------------------------------------------------------------------

  async webSocketClose(ws) {
    const att = ws.deserializeAttachment();
    if (!att) return;
    const { userId, name } = att;

    const state = await this.getState();
    const activePhases = ['betting', 'playing', 'dealer_turn'];

    this.broadcast({ type: 'player_disconnected', userId, name });

    if (!activePhases.includes(state.phase)) {
      // Not in a round — 5-minute cleanup window
      setTimeout(async () => {
        const s = await this.getState();
        // If still disconnected (no reconnect), treat as leave
        const sockets = this.ctx.getWebSockets();
        const isReconnected = sockets.some(sock => {
          const a = sock.deserializeAttachment();
          return a && a.userId === userId;
        });
        if (!isReconnected) {
          const idx = s.players.findIndex(p => p.userId === userId);
          if (idx !== -1) {
            s.players.splice(idx, 1);
            s.players.forEach((p, i) => { p.seatIndex = i; });
            if (s.creatorId === userId && s.players.length > 0) {
              s.creatorId = s.players[0].userId;
            }
            await this.saveState(s);
            this.broadcast({ type: 'player_left', userId, name });
            if (s.gameId) {
              try {
                await this.env.DB.prepare(
                  'UPDATE blackjack_mp_games SET player_count = ? WHERE id = ?'
                ).bind(s.players.length, s.gameId).run();
              } catch (_) {}
            }
          }
        }
      }, 5 * 60 * 1000);
    } else {
      // In active round — 30s auto-stand if it's their turn
      const player = state.players.find(p => p.userId === userId);
      if (player && state.phase === 'playing' && state.players[state.currentTurn]?.userId === userId) {
        setTimeout(async () => {
          const s = await this.getState();
          const p2 = s.players.find(p => p.userId === userId);
          if (p2 && p2.status === 'playing') {
            p2.status = 'stood';
            this.broadcast({ type: 'player_stood', userId, name, hand: p2.hand, value: p2.value });
            await this.saveState(s);
            await this.nextTurn(s);
          }
        }, 30000);
      }
    }

    await this.saveState(state);
  }

  webSocketError(ws) { this.webSocketClose(ws); }

  // -------------------------------------------------------------------------
  // Broadcast / sendTo
  // -------------------------------------------------------------------------

  broadcast(data) {
    const msg = JSON.stringify(data);
    this.ctx.getWebSockets().forEach(ws => { try { ws.send(msg); } catch (_) {} });
  }

  sendTo(userId, data) {
    const msg = JSON.stringify(data);
    this.ctx.getWebSockets().forEach(ws => {
      const att = ws.deserializeAttachment();
      if (att && att.userId === userId) {
        try { ws.send(msg); } catch (_) {}
      }
    });
  }

  // -------------------------------------------------------------------------
  // Game state snapshot (hides dealer hole card during play)
  // -------------------------------------------------------------------------

  getGameStateFor(userId, state) {
    const hidingHole = state.phase === 'playing';
    return {
      gameId: state.gameId,
      phase: state.phase,
      creatorId: state.creatorId,
      currentTurn: state.currentTurn,
      players: state.players.map(p => ({
        userId: p.userId,
        name: p.name,
        seatIndex: p.seatIndex,
        balance: p.balance,
        bet: p.bet,
        hand: p.hand,
        value: p.value,
        status: p.status,
        hasActed: p.hasActed,
      })),
      dealer: hidingHole && state.dealer.hand.length > 0
        ? {
            hand: [state.dealer.hand[0], { suit: 'hidden', rank: 'hidden' }],
            value: cardValue(state.dealer.hand[0]),
          }
        : {
            hand: state.dealer.hand,
            value: state.dealer.value,
          },
    };
  }

  // -------------------------------------------------------------------------
  // Internal utilities
  // -------------------------------------------------------------------------

  /** Collect all cards currently in hands (for deck reshuffle exclusion). */
  _allInPlayCards(state) {
    const cards = [...state.dealer.hand];
    for (const p of state.players) {
      cards.push(...p.hand);
    }
    return cards;
  }

  /** Set a turn timeout that auto-stands the given player if still their turn. */
  _setTurnTimeout(userId, ms) {
    setTimeout(async () => {
      const s = await this.getState();
      if (s.phase !== 'playing') return;
      const player = s.players[s.currentTurn];
      if (!player || player.userId !== userId || player.status !== 'playing') return;
      // Auto-stand
      player.status = 'stood';
      this.broadcast({ type: 'player_stood', userId, name: player.name, hand: player.hand, value: player.value });
      await this.saveState(s);
      await this.nextTurn(s);
    }, ms);
  }
}

// ---------------------------------------------------------------------------
// Default export — routes /join/:gameId to the Durable Object
// ---------------------------------------------------------------------------

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const joinMatch = url.pathname.match(/^\/join\/(.+)$/);
    if (joinMatch) {
      const gameId = joinMatch[1];
      const id = env.BLACKJACK_GAME.idFromName(gameId);
      const stub = env.BLACKJACK_GAME.get(id);
      return stub.fetch(request);
    }
    return new Response('Not found', { status: 404 });
  }
};
