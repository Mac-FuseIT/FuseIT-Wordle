import { requireAuth, errorResponse } from '../../../src/db.js';
import { getToday } from '../../../src/db.js';

function getDailyBotLevel(dateStr) {
  let h = 0xdeadbeef;
  const s = 'chess:' + dateStr;
  for (let i = 0; i < s.length; i++) {
    h = Math.imul(h ^ s.charCodeAt(i), 2654435761);
    h = (h << 13) | (h >>> 19);
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507);
  h = (h ^ (h >>> 16)) >>> 0;
  return Math.round((100 + (h % 1401)) / 2);
}

function getDailyPlayerColor(dateStr) {
  let h = 0xbaadf00d;
  const s = 'pcolor:' + dateStr;
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
  const botLevel = getDailyBotLevel(date);
  const playerColor = getDailyPlayerColor(date);

  const completed = await env.DB.prepare(
    'SELECT won, moves, redos_used FROM phantom_chess_games WHERE user_id = ? AND date = ?'
  ).bind(auth.userId, date).first();

  let session = null;
  try {
    const row = await env.DB.prepare(
      'SELECT fen, move_history, move_count, redos_used FROM phantom_chess_sessions WHERE user_id = ? AND date = ?'
    ).bind(auth.userId, date).first();
    if (row) {
      session = { fen: row.fen, moveHistory: JSON.parse(row.move_history), moveCount: row.move_count, redosUsed: row.redos_used };
    }
  } catch (_) {}

  return new Response(JSON.stringify({
    date, botLevel, playerColor,
    played: !!completed,
    won: completed?.won ?? null,
    moves: completed?.moves ?? null,
    redosUsed: completed?.redos_used ?? 0,
    session,
  }), { headers: { 'Content-Type': 'application/json' } });
}
