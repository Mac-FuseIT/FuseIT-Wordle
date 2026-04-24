import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const month = date.substring(0, 7);
  const monthStart = month + '-01';

  const daily = await env.DB.prepare(
    'SELECT u.name, sa.hints_used AS hintsUsed, sa.completed AS solved FROM strand_attempts sa JOIN users u ON u.id = sa.user_id WHERE sa.date = ? ORDER BY sa.completed DESC, sa.hints_used ASC'
  ).bind(date).all();

  const monthly = await env.DB.prepare(
    'SELECT u.name, CAST(ROUND(AVG(sa.hints_used)) AS INTEGER) AS avgHints, COUNT(sa.id) AS daysPlayed FROM strand_attempts sa JOIN users u ON u.id = sa.user_id WHERE sa.date >= ? AND sa.date <= ? GROUP BY u.id ORDER BY avgHints ASC'
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
