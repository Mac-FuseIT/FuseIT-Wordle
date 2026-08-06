import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;
  const date = getToday();
  const monthStart = date.substring(0, 7) + '-01';

  // Daily leaderboard (today, sorted by steps ascending)
  const daily = await env.DB.prepare(
    `SELECT u.name, ca.steps
     FROM chainit_attempts ca
     JOIN users u ON u.id = ca.user_id
     WHERE ca.date = ?
     ORDER BY ca.steps ASC
     LIMIT 50`
  ).bind(date).all();

  // Monthly leaderboard — penalize unplayed days with (word_length + 10) steps
  // Only includes users who played at least once this month
  const monthly = await env.DB.prepare(
    `WITH month_days AS (
       SELECT date, length FROM chainit_puzzles WHERE date >= ? AND date <= ?
     ),
     user_scores AS (
       SELECT u.id, u.name,
         SUM(COALESCE(ca.steps, md.length + 10)) AS totalSteps,
         COUNT(ca.id) AS daysPlayed
       FROM users u
       CROSS JOIN month_days md
       LEFT JOIN chainit_attempts ca ON ca.user_id = u.id AND ca.date = md.date
       WHERE EXISTS (
         SELECT 1 FROM chainit_attempts WHERE user_id = u.id AND date >= ? AND date <= ?
       )
       GROUP BY u.id
     )
     SELECT name, totalSteps, daysPlayed FROM user_scores ORDER BY totalSteps ASC LIMIT 50`
  ).bind(monthStart, date, monthStart, date).all();

  // History — current user's last 10 days
  const history = await env.DB.prepare(
    `SELECT cp.date, cp.start_word, cp.target_word, ca.steps
     FROM chainit_puzzles cp
     LEFT JOIN chainit_attempts ca ON ca.date = cp.date AND ca.user_id = ?
     WHERE cp.date <= ?
     ORDER BY cp.date DESC
     LIMIT 10`
  ).bind(userId, date).all();

  return jsonResponse({
    daily: (daily.results || []).map(r => ({ name: r.name, steps: r.steps })),
    monthly: (monthly.results || []).map(r => ({
      name: r.name,
      totalSteps: r.totalSteps,
      daysPlayed: r.daysPlayed,
    })),
    history: (history.results || []).map(r => ({
      date: r.date,
      startWord: r.start_word,
      targetWord: r.target_word,
      steps: r.steps,
    })),
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
