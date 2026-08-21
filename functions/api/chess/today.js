import { requireAuth, errorResponse } from '../../../src/db.js';
import { getToday } from '../../../src/db.js';

function seededHash(seed) {
  let h = 0xdeadbeef;
  for (let i = 0; i < seed.length; i++) {
    h = Math.imul(h ^ seed.charCodeAt(i), 2654435761);
    h = (h << 13) | (h >>> 19);
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507);
  h = (h ^ (h >>> 16)) >>> 0;
  return h;
}

function getDailyBotLevel(dateStr) {
  const h = seededHash('chess:' + dateStr);

  // Weighted skill level selection (0-20)
  // Lower levels are more likely (friendlier for office players)
  const weights = [20, 18, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 3, 2, 2, 1, 1];
  const totalWeight = weights.reduce((a, b) => a + b, 0);
  let roll = h % totalWeight;
  let skillLevel = 0;
  for (let i = 0; i < weights.length; i++) {
    roll -= weights[i];
    if (roll < 0) {
      skillLevel = i;
      break;
    }
  }

  return skillLevel;
}

function getDailyAmateurElo(dateStr) {
  // Generate an amateur ELO between 100-900 using a different seed
  const h = seededHash('chess-amateur:' + dateStr);
  // Pick from [100, 200, 300, 400, 500, 600, 700, 800, 900]
  // Weighted toward lower values
  const levels = [100, 200, 300, 400, 500, 600, 700, 800, 900];
  const weights = [15, 14, 13, 12, 10, 8, 6, 4, 2];
  const totalWeight = weights.reduce((a, b) => a + b, 0);
  let roll = h % totalWeight;
  let elo = levels[0];
  for (let i = 0; i < weights.length; i++) {
    roll -= weights[i];
    if (roll < 0) {
      elo = levels[i];
      break;
    }
  }
  return elo;
}

function getDailyPlayerColor(dateStr) {
  const h = seededHash('color:' + dateStr);
  return h % 2 === 0 ? 'white' : 'black';
}

function getDailyAmateurPlayerColor(dateStr) {
  const h = seededHash('color-amateur:' + dateStr);
  return h % 2 === 0 ? 'white' : 'black';
}

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const url = new URL(request.url);
  const mode = url.searchParams.get('mode') || 'expert';

  const date = getToday();

  if (mode === 'amateur') {
    const amateurElo = getDailyAmateurElo(date);
    const playerColor = getDailyAmateurPlayerColor(date);

    const completed = await env.DB.prepare(
      'SELECT won, moves, redos_used FROM chess_games WHERE user_id = ? AND date = ? AND mode = ?'
    ).bind(auth.userId, date, 'amateur').first();

    const session = await env.DB.prepare(
      'SELECT fen, move_history, move_count, redos_used FROM chess_sessions WHERE user_id = ? AND date = ? AND mode = ?'
    ).bind(auth.userId, date, 'amateur').first();

    return new Response(JSON.stringify({
      date,
      mode: 'amateur',
      botLevel: amateurElo,
      eloRange: `${amateurElo} ELO`,
      playerColor,
      played: !!completed,
      won: completed?.won ?? null,
      moves: completed?.moves ?? null,
      redosUsed: completed?.redos_used ?? 0,
      session: session ? {
        fen: session.fen,
        moveHistory: JSON.parse(session.move_history),
        moveCount: session.move_count,
        redosUsed: session.redos_used,
      } : null,
    }), { headers: { 'Content-Type': 'application/json' } });
  }

  // Expert mode (default) - same as before
  const skillLevel = getDailyBotLevel(date);
  const eloRanges = [
    '1000-1100', '1100-1200', '1200-1300', '1300-1400', '1400-1450',
    '1450-1500', '1500-1550', '1550-1600', '1600-1650', '1650-1700',
    '1700-1750', '1750-1800', '1800-1900', '1900-2000', '2000-2100',
    '2100-2200', '2200-2400', '2400-2600', '2600-2800', '2800-3000', '3500+',
  ];
  const eloRange = eloRanges[skillLevel] ?? 'Unknown';
  const playerColor = getDailyPlayerColor(date);

  const completed = await env.DB.prepare(
    'SELECT won, moves, redos_used FROM chess_games WHERE user_id = ? AND date = ? AND mode = ?'
  ).bind(auth.userId, date, 'expert').first();

  const session = await env.DB.prepare(
    'SELECT fen, move_history, move_count, redos_used FROM chess_sessions WHERE user_id = ? AND date = ? AND mode = ?'
  ).bind(auth.userId, date, 'expert').first();

  return new Response(JSON.stringify({
    date,
    mode: 'expert',
    botLevel: skillLevel,
    eloRange,
    playerColor,
    played: !!completed,
    won: completed?.won ?? null,
    moves: completed?.moves ?? null,
    redosUsed: completed?.redos_used ?? 0,
    session: session ? {
      fen: session.fen,
      moveHistory: JSON.parse(session.move_history),
      moveCount: session.move_count,
      redosUsed: session.redos_used,
    } : null,
  }), { headers: { 'Content-Type': 'application/json' } });
}
