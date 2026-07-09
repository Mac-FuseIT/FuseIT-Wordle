import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

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

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;

  const today = getToday();

  let row = await env.DB.prepare(
    'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  let session;
  if (!row) {
    session = defaultSession();
    await env.DB.prepare(
      'INSERT INTO blackjack_sessions (user_id, date, session_state) VALUES (?, ?, ?)'
    ).bind(userId, today, JSON.stringify(session)).run();
  } else {
    session = JSON.parse(row.session_state);
  }

  // Check if already cashed out today
  const cashoutRow = await env.DB.prepare(
    'SELECT final_balance FROM blackjack_results WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  return jsonResponse({
    balance: session.balance,
    deckRemaining: session.deck.length,
    playerHand: session.playerHand,
    dealerHand: session.currentBet > 0 && !session.gameOver
      ? [session.dealerHand[0], { suit: 'hidden', rank: 'hidden' }]
      : session.dealerHand,
    currentBet: session.currentBet,
    handsPlayed: session.handsPlayed,
    handsWon: session.handsWon,
    blackjacks: session.blackjacks,
    gameOver: session.gameOver,
    cashedOut: !!cashoutRow,
    inHand: session.currentBet > 0 && !session.gameOver,
  });
}
