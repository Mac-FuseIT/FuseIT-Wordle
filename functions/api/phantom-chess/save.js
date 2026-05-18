import { requireAuth, errorResponse } from '../../../src/db.js';
import { getToday } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const { fen, moveHistory, moveCount, redosUsed } = await request.json();

  if (!fen || !Array.isArray(moveHistory) || typeof moveCount !== 'number') {
    return errorResponse('Missing fields', 400);
  }

  const completed = await env.DB.prepare(
    'SELECT id FROM phantom_chess_games WHERE user_id = ? AND date = ?'
  ).bind(auth.userId, date).first();
  if (completed) return errorResponse('Already completed', 403);

  await env.DB.prepare(
    `INSERT INTO phantom_chess_sessions (user_id, date, fen, move_history, move_count, redos_used)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id, date) DO UPDATE SET fen = ?, move_history = ?, move_count = ?, redos_used = ?`
  ).bind(
    auth.userId, date, fen, JSON.stringify(moveHistory), moveCount, redosUsed || 0,
    fen, JSON.stringify(moveHistory), moveCount, redosUsed || 0
  ).run();

  return new Response(JSON.stringify({ success: true }), { headers: { 'Content-Type': 'application/json' } });
}
