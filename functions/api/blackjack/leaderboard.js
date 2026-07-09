import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const today = getToday();
  const monthStart = today.substring(0, 7) + '-01';

  // Daily leaderboard: combine cashed-out results AND active sessions
  const dailyResults = await env.DB.prepare(
    `SELECT u.name as nickname, (br.final_balance - 100) as profit, br.final_balance, br.hands_played, br.hands_won, 1 as cashed_out
     FROM blackjack_results br
     JOIN users u ON u.id = br.user_id
     WHERE br.date = ?
     UNION ALL
     SELECT u.name as nickname, (json_extract(bs.session_state, '$.balance') - 100) as profit, json_extract(bs.session_state, '$.balance') as final_balance, json_extract(bs.session_state, '$.handsPlayed') as hands_played, json_extract(bs.session_state, '$.handsWon') as hands_won, 0 as cashed_out
     FROM blackjack_sessions bs
     JOIN users u ON u.id = bs.user_id
     WHERE bs.date = ?
       AND NOT EXISTS (SELECT 1 FROM blackjack_results br2 WHERE br2.user_id = bs.user_id AND br2.date = bs.date)
     ORDER BY profit DESC
     LIMIT 50`
  ).bind(today, today).all();

  // Monthly leaderboard: sum of all cashed-out results + today's active sessions
  const monthlyResults = await env.DB.prepare(
    `SELECT nickname, SUM(profit) as total_profit, SUM(hands) as total_hands, COUNT(*) as games FROM (
       SELECT u.name as nickname, (br.final_balance - 100) as profit, br.hands_played as hands, br.user_id
       FROM blackjack_results br
       JOIN users u ON u.id = br.user_id
       WHERE br.date >= ? AND br.date <= ?
       UNION ALL
       SELECT u.name as nickname, (json_extract(bs.session_state, '$.balance') - 100) as profit, json_extract(bs.session_state, '$.handsPlayed') as hands, bs.user_id
       FROM blackjack_sessions bs
       JOIN users u ON u.id = bs.user_id
       WHERE bs.date = ?
         AND NOT EXISTS (SELECT 1 FROM blackjack_results br2 WHERE br2.user_id = bs.user_id AND br2.date = bs.date)
     )
     GROUP BY user_id
     ORDER BY total_profit DESC
     LIMIT 50`
  ).bind(monthStart, today, today).all();

  return jsonResponse({
    daily: dailyResults.results || [],
    monthly: monthlyResults.results || [],
    date: today,
  });
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}
