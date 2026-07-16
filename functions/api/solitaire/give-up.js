import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

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
  if (state.status !== 'in_progress') return errorResponse('Game already over', 400);

  // Calculate time
  const startedAt = row.started_at;
  const timeSeconds = startedAt
    ? Math.floor((Date.now() - new Date(startedAt).getTime()) / 1000)
    : 0;

  // Mark as gave up
  state.status = 'gave_up';
  await env.DB.prepare(
    'UPDATE solitaire_sessions SET session_state = ?, updated_at = datetime("now") WHERE user_id = ? AND date = ?'
  ).bind(JSON.stringify(state), userId, today).run();

  // Record result (1 point for trying)
  await env.DB.prepare(
    'INSERT OR IGNORE INTO solitaire_results (user_id, date, completed, moves, time_seconds, points) VALUES (?, ?, 0, ?, ?, 1)'
  ).bind(userId, today, state.moves, timeSeconds).run();

  return jsonResponse({
    ok: true,
    status: 'gave_up',
    points: 1,
    moves: state.moves,
    time_seconds: timeSeconds,
  });
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
