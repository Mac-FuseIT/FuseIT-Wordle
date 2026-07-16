import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

const RANK_ORDER = ['A','2','3','4','5','6','7','8','9','10','J','Q','K'];

function getRank(card) { return card.slice(0, -1); }
function getSuit(card) { return card.slice(-1); }
function isRed(card) { return 'hd'.includes(getSuit(card)); }
function isBlack(card) { return 'cs'.includes(getSuit(card)); }
function rankValue(card) { return RANK_ORDER.indexOf(getRank(card)); }

function suitName(suitChar) {
  const map = { h: 'hearts', d: 'diamonds', c: 'clubs', s: 'spades' };
  return map[suitChar] || '';
}

function checkWin(state) {
  return Object.values(state.foundations).reduce((sum, pile) => sum + pile.length, 0) === 52;
}

function calculatePoints(completed, moves, timeSeconds) {
  let points = completed ? 10 : 1;
  if (completed) {
    if (timeSeconds < 120) points += 5;
    else if (timeSeconds < 300) points += 3;
    else if (timeSeconds < 600) points += 1;
    if (moves < 80) points += 5;
    else if (moves < 120) points += 3;
    else if (moves < 160) points += 1;
  }
  return points;
}

// Auto-move: check if any Aces or 2s can safely go to foundation
function findAutoMoves(state) {
  const autoMoved = [];
  let found = true;
  while (found) {
    found = false;
    // Check waste top
    if (state.waste.length > 0) {
      const card = state.waste[state.waste.length - 1];
      if (canAutoMove(card, state)) {
        state.waste.pop();
        state.foundations[suitName(getSuit(card))].push(card);
        autoMoved.push(card);
        found = true;
        continue;
      }
    }
    // Check tableau tops
    for (const col of state.tableau) {
      if (col.visible.length > 0) {
        const card = col.visible[col.visible.length - 1];
        if (canAutoMove(card, state)) {
          col.visible.pop();
          state.foundations[suitName(getSuit(card))].push(card);
          autoMoved.push(card);
          // Flip hidden card if needed
          if (col.visible.length === 0 && col.hidden.length > 0) {
            col.visible.push(col.hidden.pop());
          }
          found = true;
          break; // restart loop
        }
      }
    }
  }
  return autoMoved;
}

function canAutoMove(card, state) {
  const rank = getRank(card);
  if (rank === 'A') return true;
  if (rank === '2') {
    const foundPile = state.foundations[suitName(getSuit(card))];
    return foundPile.length === 1 && getRank(foundPile[0]) === 'A';
  }
  return false;
}

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;
  const today = getToday();

  const row = await env.DB.prepare(
    'SELECT session_state, started_at FROM solitaire_sessions WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();
  if (!row) return errorResponse('No session found', 400);

  const state = JSON.parse(row.session_state);
  if (state.status !== 'in_progress') return errorResponse('Game is over', 400);

  const body = await request.json();
  const { from, to } = body;

  if (!from || !to) return errorResponse('Missing from/to', 400);

  // Set started_at on first action
  let startedAt = row.started_at;
  if (!startedAt) {
    startedAt = new Date().toISOString();
    await env.DB.prepare(
      'UPDATE solitaire_sessions SET started_at = ? WHERE user_id = ? AND date = ?'
    ).bind(startedAt, userId, today).run();
  }

  // Extract source card(s)
  let movingCards = [];

  if (from.zone === 'waste') {
    if (state.waste.length === 0) return errorResponse('Waste is empty', 400);
    movingCards = [state.waste[state.waste.length - 1]];
  } else if (from.zone === 'tableau') {
    const col = state.tableau[from.col];
    if (!col) return errorResponse('Invalid column', 400);
    const cardIndex = from.cardIndex ?? (col.visible.length - 1);
    if (cardIndex < 0 || cardIndex >= col.visible.length) return errorResponse('Invalid card index', 400);
    movingCards = col.visible.slice(cardIndex);
  } else if (from.zone === 'foundation') {
    const pile = state.foundations[from.suit];
    if (!pile || pile.length === 0) return errorResponse('Foundation is empty', 400);
    movingCards = [pile[pile.length - 1]];
  } else {
    return errorResponse('Invalid from zone', 400);
  }

  if (movingCards.length === 0) return errorResponse('No cards to move', 400);
  const bottomCard = movingCards[0];

  // Validate destination and apply
  let valid = false;

  if (to.zone === 'tableau') {
    const destCol = state.tableau[to.col];
    if (!destCol) return errorResponse('Invalid destination column', 400);

    if (destCol.visible.length === 0 && destCol.hidden.length === 0) {
      // Empty column: only King can go
      if (getRank(bottomCard) === 'K') valid = true;
    } else if (destCol.visible.length > 0) {
      const topCard = destCol.visible[destCol.visible.length - 1];
      // Must be one rank lower and opposite color
      if (rankValue(bottomCard) === rankValue(topCard) - 1 &&
          isRed(bottomCard) !== isRed(topCard)) {
        valid = true;
      }
    }

    if (valid) {
      // Remove from source
      if (from.zone === 'waste') {
        state.waste.pop();
      } else if (from.zone === 'tableau') {
        const srcCol = state.tableau[from.col];
        srcCol.visible.splice(from.cardIndex ?? (srcCol.visible.length - 1));
        if (srcCol.visible.length === 0 && srcCol.hidden.length > 0) {
          srcCol.visible.push(srcCol.hidden.pop());
        }
      } else if (from.zone === 'foundation') {
        state.foundations[from.suit].pop();
      }
      // Add to destination
      destCol.visible.push(...movingCards);
    }
  } else if (to.zone === 'foundation') {
    if (movingCards.length !== 1) return errorResponse('Can only move one card to foundation', 400);
    const card = movingCards[0];
    const suit = suitName(getSuit(card));
    if (to.suit && to.suit !== suit) return errorResponse('Wrong suit', 400);
    const pile = state.foundations[suit];

    if (pile.length === 0) {
      if (getRank(card) === 'A') valid = true;
    } else {
      const topCard = pile[pile.length - 1];
      if (rankValue(card) === rankValue(topCard) + 1 && getSuit(card) === getSuit(topCard)) {
        valid = true;
      }
    }

    if (valid) {
      if (from.zone === 'waste') {
        state.waste.pop();
      } else if (from.zone === 'tableau') {
        const srcCol = state.tableau[from.col];
        srcCol.visible.pop();
        if (srcCol.visible.length === 0 && srcCol.hidden.length > 0) {
          srcCol.visible.push(srcCol.hidden.pop());
        }
      } else if (from.zone === 'foundation') {
        state.foundations[from.suit].pop();
      }
      pile.push(card);
    }
  } else {
    return errorResponse('Invalid destination zone', 400);
  }

  if (!valid) return jsonResponse({ ok: false, error: 'Invalid move' });

  state.moves++;

  // Auto-move Aces and 2s
  const autoMoved = findAutoMoves(state);

  // Check win
  const won = checkWin(state);
  if (won) {
    state.status = 'won';
    const timeSeconds = Math.floor((Date.now() - new Date(startedAt).getTime()) / 1000);
    const points = calculatePoints(true, state.moves, timeSeconds);

    await env.DB.prepare(
      'INSERT OR IGNORE INTO solitaire_results (user_id, date, completed, moves, time_seconds, points) VALUES (?, ?, 1, ?, ?, ?)'
    ).bind(userId, today, state.moves, timeSeconds, points).run();
  }

  // Save state
  await env.DB.prepare(
    'UPDATE solitaire_sessions SET session_state = ?, updated_at = datetime("now") WHERE user_id = ? AND date = ?'
  ).bind(JSON.stringify(state), userId, today).run();

  // Build response
  const elapsed = Math.floor((Date.now() - new Date(startedAt).getTime()) / 1000);
  const response = {
    ok: true,
    state: {
      status: state.status,
      stock_count: state.stock.length,
      waste_top: state.waste.slice(-3),
      waste_count: state.waste.length,
      foundations: {
        hearts: state.foundations.hearts.length,
        diamonds: state.foundations.diamonds.length,
        clubs: state.foundations.clubs.length,
        spades: state.foundations.spades.length,
      },
      tableau: state.tableau.map(col => ({
        hidden: col.hidden.length,
        visible: col.visible,
      })),
      moves: state.moves,
      elapsed_seconds: elapsed,
    },
    auto_moved: autoMoved,
    won,
  };

  if (won) {
    const timeSeconds = Math.floor((Date.now() - new Date(startedAt).getTime()) / 1000);
    response.points = calculatePoints(true, state.moves, timeSeconds);
    response.time_seconds = timeSeconds;
    response.moves = state.moves;
  }

  return jsonResponse(response);
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}
