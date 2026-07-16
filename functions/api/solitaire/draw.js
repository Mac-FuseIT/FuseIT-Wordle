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
  if (state.stock.length === 0) return errorResponse('Stock is empty. Recycle the waste pile.', 400);

  // Set started_at on first action
  let startedAt = row.started_at;
  if (!startedAt) {
    startedAt = new Date().toISOString();
    await env.DB.prepare(
      'UPDATE solitaire_sessions SET started_at = ? WHERE user_id = ? AND date = ?'
    ).bind(startedAt, userId, today).run();
  }

  // Draw up to 3 cards
  const drawn = state.stock.splice(-Math.min(3, state.stock.length));
  state.waste.push(...drawn);
  state.moves++;

  await env.DB.prepare(
    'UPDATE solitaire_sessions SET session_state = ?, updated_at = datetime("now") WHERE user_id = ? AND date = ?'
  ).bind(JSON.stringify(state), userId, today).run();

  return jsonResponse({
    ok: true,
    drawn: drawn,
    stock_count: state.stock.length,
    waste_top: state.waste.slice(-3),
    waste_count: state.waste.length,
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
