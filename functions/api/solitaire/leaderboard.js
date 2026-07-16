import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const today = getToday();
  const monthStart = today.substring(0, 7) + '-01';

  // Daily leaderboard
  const daily = await env.DB.prepare(
    `SELECT u.name as nickname, sr.points, sr.moves, sr.time_seconds, sr.completed
     FROM solitaire_results sr
     JOIN users u ON u.id = sr.user_id
     WHERE sr.date = ?
     ORDER BY sr.points DESC, sr.time_seconds ASC
     LIMIT 50`
  ).bind(today).all();

  // Monthly leaderboard
  const monthly = await env.DB.prepare(
    `SELECT u.name as nickname,
            SUM(sr.points) as total_points,
            COUNT(*) as games_played,
            SUM(sr.completed) as games_won
     FROM solitaire_results sr
     JOIN users u ON u.id = sr.user_id
     WHERE sr.date >= ? AND sr.date <= ?
     GROUP BY sr.user_id
     ORDER BY total_points DESC, games_won DESC
     LIMIT 50`
  ).bind(monthStart, today).all();

  return jsonResponse({
    daily: daily.results || [],
    monthly: monthly.results || [],
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
