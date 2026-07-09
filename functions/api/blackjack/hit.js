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

function drawCard(session) {
  if (session.deck.length < 1) {
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

  const row = await env.DB.prepare(
    'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  if (!row) return errorResponse('No session found', 400);

  const session = JSON.parse(row.session_state);

  if (session.currentBet === 0 || session.gameOver) {
    return errorResponse('No active hand', 400);
  }

  const card = drawCard(session);
  session.playerHand.push(card);

  const playerVal = handValue(session.playerHand);
  let result = null;

  if (playerVal > 21) {
    // Bust - player loses
    session.gameOver = true;
    session.handsPlayed++;
    result = 'bust';
  } else if (playerVal === 21) {
    // Auto-stand on 21
    result = dealerPlay(session);
  }

  await env.DB.prepare(
    'UPDATE blackjack_sessions SET session_state = ? WHERE user_id = ? AND date = ?'
  ).bind(JSON.stringify(session), userId, today).run();

  return jsonResponse({
    card,
    playerHand: session.playerHand,
    dealerHand: session.gameOver
      ? session.dealerHand
      : [session.dealerHand[0], { suit: 'hidden', rank: 'hidden' }],
    playerValue: handValue(session.playerHand),
    dealerValue: session.gameOver ? handValue(session.dealerHand) : null,
    balance: session.balance,
    currentBet: session.currentBet,
    gameOver: session.gameOver,
    deckRemaining: session.deck.length,
    result,
  });
}

function dealerPlay(session) {
  while (handValue(session.dealerHand) < 17) {
    session.dealerHand.push(drawCard(session));
  }

  const playerVal = handValue(session.playerHand);
  const dealerVal = handValue(session.dealerHand);

  session.gameOver = true;
  session.handsPlayed++;

  if (dealerVal > 21) {
    session.balance += session.currentBet * 2;
    session.handsWon++;
    return 'dealer_bust';
  } else if (playerVal > dealerVal) {
    session.balance += session.currentBet * 2;
    session.handsWon++;
    return 'win';
  } else if (playerVal === dealerVal) {
    session.balance += session.currentBet;
    return 'push';
  } else {
    return 'lose';
  }
}
