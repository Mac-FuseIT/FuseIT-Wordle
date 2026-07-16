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
  if (state.status !== 'in_progress') return errorResponse('Game is over', 400);
  if (state.stock.length > 0) return errorResponse('Stock is not empty', 400);
  if (state.waste.length === 0) return errorResponse('Waste is empty too', 400);

  // Set started_at on first action
  let startedAt = row.started_at;
  if (!startedAt) {
    startedAt = new Date().toISOString();
    await env.DB.prepare(
      'UPDATE solitaire_sessions SET started_at = ? WHERE user_id = ? AND date = ?'
    ).bind(startedAt, userId, today).run();
  }

  // Reverse waste into stock
  state.stock = state.waste.reverse();
  state.waste = [];
  state.moves++;

  await env.DB.prepare(
    'UPDATE solitaire_sessions SET session_state = ?, updated_at = datetime("now") WHERE user_id = ? AND date = ?'
  ).bind(JSON.stringify(state), userId, today).run();

  return jsonResponse({
    ok: true,
    stock_count: state.stock.length,
    waste_top: null,
    waste_count: 0,
    moves: state.moves,
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
