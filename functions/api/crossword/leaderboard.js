import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const month = date.substring(0, 7);
  const monthStart = month + '-01';

  const daily = await env.DB.prepare(
    'SELECT u.name, ca.time_seconds AS timeSeconds FROM crossword_attempts ca JOIN users u ON u.id = ca.user_id WHERE ca.date = ? ORDER BY ca.time_seconds ASC'
  ).bind(date).all();

  const monthly = await env.DB.prepare(
    'SELECT u.name, CAST(ROUND(AVG(ca.time_seconds)) AS INTEGER) AS avgTime, COUNT(ca.id) AS daysPlayed FROM crossword_attempts ca JOIN users u ON u.id = ca.user_id WHERE ca.date >= ? AND ca.date <= ? GROUP BY u.id ORDER BY avgTime ASC'
  ).bind(monthStart, date).all();

  const user = await env.DB.prepare('SELECT nickname, name FROM users WHERE id = ?').bind(auth.userId).first();

  return jsonResponse({
    daily: daily.results || [],
    monthly: monthly.results || [],
    currentUserName: user ? (user.nickname || user.name) : null,
  });
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
