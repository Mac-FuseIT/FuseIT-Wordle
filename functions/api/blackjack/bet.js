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

function drawCard(session) {
  if (session.deck.length < 1) {
    // Reshuffle: create new deck excluding cards currently in play
    const inPlay = [...(session.playerHand || []), ...(session.dealerHand || [])];
    const full = createDeck();
    session.deck = full.filter(card =>
      !inPlay.some(p => p.suit === card.suit && p.rank === card.rank)
    );
  }
  return session.deck.pop();
}

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;

  const today = getToday();
  const body = await request.json();
  const betAmount = parseInt(body.amount);

  if (!betAmount || betAmount < 1) {
    return errorResponse('Bet must be at least 1', 400);
  }

  const row = await env.DB.prepare(
    'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  if (!row) return errorResponse('No session found. Call /api/blackjack/today first.', 400);

  const session = JSON.parse(row.session_state);

  // Check if already cashed out
  const cashoutRow = await env.DB.prepare(
    'SELECT id FROM blackjack_results WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();
  if (cashoutRow) return errorResponse('Already cashed out today', 400);

  if (session.currentBet > 0 && !session.gameOver) {
    return errorResponse('Hand already in progress', 400);
  }

  if (betAmount > session.balance) {
    return errorResponse('Insufficient balance', 400);
  }

  if (session.balance <= 0) {
    return errorResponse('No balance remaining', 400);
  }

  // Ensure enough cards
  if (session.deck.length < 4) {
    session.deck = createDeck();
  }

  session.currentBet = betAmount;
  session.balance -= betAmount;
  session.gameOver = false;
  session.playerHand = [drawCard(session), drawCard(session)];
  session.dealerHand = [drawCard(session), drawCard(session)];

  const playerBJ = isBlackjack(session.playerHand);
  const dealerBJ = isBlackjack(session.dealerHand);

  let result = null;

  if (playerBJ && dealerBJ) {
    // Push
    session.balance += session.currentBet;
    session.gameOver = true;
    session.handsPlayed++;
    result = 'push';
  } else if (playerBJ) {
    // Blackjack pays 3:2
    session.balance += session.currentBet + Math.floor(session.currentBet * 1.5);
    session.gameOver = true;
    session.handsPlayed++;
    session.handsWon++;
    session.blackjacks++;
    result = 'blackjack';
  } else if (dealerBJ) {
    // Dealer blackjack, player loses bet (already deducted)
    session.gameOver = true;
    session.handsPlayed++;
    result = 'dealer_blackjack';
  }

  await env.DB.prepare(
    'UPDATE blackjack_sessions SET session_state = ? WHERE user_id = ? AND date = ?'
  ).bind(JSON.stringify(session), userId, today).run();

  return jsonResponse({
    playerHand: session.playerHand,
    dealerHand: session.gameOver
      ? session.dealerHand
      : [session.dealerHand[0], { suit: 'hidden', rank: 'hidden' }],
    playerValue: handValue(session.playerHand),
    balance: session.balance,
    currentBet: session.currentBet,
    gameOver: session.gameOver,
    deckRemaining: session.deck.length,
    result,
  });
}
