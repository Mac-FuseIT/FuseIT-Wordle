import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;

  const today = getToday();

  // Check if actually cashed out
  const existing = await env.DB.prepare(
    'SELECT id FROM blackjack_results WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  if (!existing) return errorResponse('Not cashed out', 400);

  // Delete the cashout record
  await env.DB.prepare(
    'DELETE FROM blackjack_results WHERE user_id = ? AND date = ?'
  ).bind(userId, today).run();

  // Return current session state
  const row = await env.DB.prepare(
    'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  const session = row ? JSON.parse(row.session_state) : { balance: 100 };

  return jsonResponse({
    balance: session.balance,
    cashedOut: false,
  });
}
