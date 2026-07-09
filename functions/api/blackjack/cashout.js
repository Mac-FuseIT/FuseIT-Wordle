import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;

  const today = getToday();

  // Check if already cashed out
  const existing = await env.DB.prepare(
    'SELECT id FROM blackjack_results WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  if (existing) return errorResponse('Already cashed out today', 400);

  const row = await env.DB.prepare(
    'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  if (!row) return errorResponse('No session found', 400);

  const session = JSON.parse(row.session_state);

  // Cannot cash out mid-hand
  if (session.currentBet > 0 && !session.gameOver) {
    return errorResponse('Cannot cash out during an active hand', 400);
  }

  // Record results
  await env.DB.prepare(
    `INSERT INTO blackjack_results (user_id, date, final_balance, hands_played, hands_won, blackjacks)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).bind(userId, today, session.balance, session.handsPlayed, session.handsWon, session.blackjacks).run();

  const profit = session.balance - 100;

  return jsonResponse({
    finalBalance: session.balance,
    profit,
    handsPlayed: session.handsPlayed,
    handsWon: session.handsWon,
    blackjacks: session.blackjacks,
  });
}
