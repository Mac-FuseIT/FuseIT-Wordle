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
  return 100 + (h % 1401);
}

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const botLevel = getDailyBotLevel(date);

  const completed = await env.DB.prepare(
    'SELECT won, moves, redos_used FROM chess_games WHERE user_id = ? AND date = ?'
  ).bind(auth.userId, date).first();

  const session = await env.DB.prepare(
    'SELECT fen, move_history, move_count, redos_used FROM chess_sessions WHERE user_id = ? AND date = ?'
  ).bind(auth.userId, date).first();

  return new Response(JSON.stringify({
    date,
    botLevel,
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
