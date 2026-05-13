import { requireAuth, errorResponse } from '../../../src/db.js';
import { getToday } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const { won, moves, redosUsed, fen, moveHistory } = await request.json();

  if (typeof won !== 'boolean' || typeof moves !== 'number') {
    return errorResponse('Missing fields', 400);
  }

  const existing = await env.DB.prepare(
    'SELECT id FROM chess_games WHERE user_id = ? AND date = ?'
  ).bind(auth.userId, date).first();
  if (existing) return errorResponse('Already played today', 403);

  // Validate: move count must match moveHistory length (player moves only)
  if (Array.isArray(moveHistory)) {
    const playerMoves = moveHistory.filter((_, i) => i % 2 === 0).length;
    if (playerMoves !== moves) {
      return errorResponse('Move count mismatch', 403);
    }
  }

  await env.DB.prepare(
    `INSERT INTO chess_games (user_id, date, bot_level, won, moves, redos_used, completed_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    auth.userId, date,
    getDailyBotLevel(date),
    won ? 1 : 0, moves, redosUsed || 0,
    new Date().toISOString()
  ).run();

  // Clean up session
  await env.DB.prepare(
    'DELETE FROM chess_sessions WHERE user_id = ? AND date = ?'
  ).bind(auth.userId, date).run();

  return new Response(JSON.stringify({ success: true }), {
    headers: { 'Content-Type': 'application/json' }
  });
}

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
