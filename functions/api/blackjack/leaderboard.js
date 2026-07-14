import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const today = getToday();
  const monthStart = today.substring(0, 7) + '-01';

  // Daily leaderboard: combine cashed-out results AND active sessions
  // user_id is included so we can merge roulette stats below
  const dailyResults = await env.DB.prepare(
    `SELECT u.name as nickname, br.user_id, (br.final_balance - 100) as profit, br.final_balance, br.hands_played, br.hands_won, 1 as cashed_out
     FROM blackjack_results br
     JOIN users u ON u.id = br.user_id
     WHERE br.date = ?
     UNION ALL
     SELECT u.name as nickname, bs.user_id, (json_extract(bs.session_state, '$.balance') - 100) as profit, json_extract(bs.session_state, '$.balance') as final_balance, json_extract(bs.session_state, '$.handsPlayed') as hands_played, json_extract(bs.session_state, '$.handsWon') as hands_won, 0 as cashed_out
     FROM blackjack_sessions bs
     JOIN users u ON u.id = bs.user_id
     WHERE bs.date = ?
       AND NOT EXISTS (SELECT 1 FROM blackjack_results br2 WHERE br2.user_id = bs.user_id AND br2.date = bs.date)
     ORDER BY profit DESC
     LIMIT 50`
  ).bind(today, today).all();

  // Fetch today's roulette stats and build a map keyed by user_id
  const rouletteToday = await env.DB.prepare(
    'SELECT user_id, spins_played FROM roulette_results WHERE date = ?'
  ).bind(today).all();

  const rouletteMapDaily = {};
  for (const r of (rouletteToday.results || [])) {
    rouletteMapDaily[r.user_id] = r.spins_played;
  }

  // Merge spins_played into daily results
  const daily = (dailyResults.results || []).map(row => ({
    ...row,
    spins_played: rouletteMapDaily[row.user_id] || 0,
  }));

  // Monthly leaderboard: sum of all cashed-out results + all uncashed sessions for the month
  const monthlyResults = await env.DB.prepare(
    `SELECT nickname, user_id, SUM(profit) as total_profit, SUM(hands) as total_hands, COUNT(*) as games FROM (
       SELECT u.name as nickname, br.user_id, (br.final_balance - 100) as profit, br.hands_played as hands
       FROM blackjack_results br
       JOIN users u ON u.id = br.user_id
       WHERE br.date >= ? AND br.date <= ?
       UNION ALL
       SELECT u.name as nickname, bs.user_id, (json_extract(bs.session_state, '$.balance') - 100) as profit, json_extract(bs.session_state, '$.handsPlayed') as hands
       FROM blackjack_sessions bs
       JOIN users u ON u.id = bs.user_id
       WHERE bs.date >= ? AND bs.date <= ?
         AND NOT EXISTS (SELECT 1 FROM blackjack_results br2 WHERE br2.user_id = bs.user_id AND br2.date = bs.date)
     )
     GROUP BY user_id
     ORDER BY total_profit DESC
     LIMIT 50`
  ).bind(monthStart, today, monthStart, today).all();

  // Fetch this month's roulette stats and build a map keyed by user_id
  const rouletteMonthly = await env.DB.prepare(
    'SELECT user_id, SUM(spins_played) as spins_played FROM roulette_results WHERE date >= ? AND date <= ? GROUP BY user_id'
  ).bind(monthStart, today).all();

  const rouletteMapMonthly = {};
  for (const r of (rouletteMonthly.results || [])) {
    rouletteMapMonthly[r.user_id] = r.spins_played;
  }

  // Merge spins_played into monthly results
  const monthly = (monthlyResults.results || []).map(row => ({
    ...row,
    spins_played: rouletteMapMonthly[row.user_id] || 0,
  }));

  return jsonResponse({
    daily,
    monthly,
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
