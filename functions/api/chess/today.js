import { requireAuth, errorResponse } from '../../../src/db.js';
import { getToday } from '../../../src/db.js';

function getDailyBotLevel(dateStr) {
  // Seeded RNG from date
  let h = 0xdeadbeef;
  const s = 'chess:' + dateStr;
  for (let i = 0; i < s.length; i++) {
    h = Math.imul(h ^ s.charCodeAt(i), 2654435761);
    h = (h << 13) | (h >>> 19);
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507);
  h = (h ^ (h >>> 16)) >>> 0;

  // Weighted skill level selection (0-20)
  // Lower levels are more likely (friendlier for office players)
  // Weights: level 0 has weight 20, level 1 has 18, ... level 20 has 1
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

function getDailyPlayerColor(dateStr) {
  let h = 0xbaadf00d;
  const s = 'color:' + dateStr;
  for (let i = 0; i < s.length; i++) {
    h = Math.imul(h ^ s.charCodeAt(i), 2654435761);
    h = (h << 13) | (h >>> 19);
  }
  h = (h ^ (h >>> 16)) >>> 0;
  return h % 2 === 0 ? 'white' : 'black';
}

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
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
    'SELECT won, moves, redos_used FROM chess_games WHERE user_id = ? AND date = ?'
  ).bind(auth.userId, date).first();

  const session = await env.DB.prepare(
    'SELECT fen, move_history, move_count, redos_used FROM chess_sessions WHERE user_id = ? AND date = ?'
  ).bind(auth.userId, date).first();

  return new Response(JSON.stringify({
    date,
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
