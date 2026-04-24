import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { grid, elapsed } = await request.json();
  const date = getToday();

  // Check not already completed
  const attempt = await env.DB.prepare('SELECT id FROM crossword_attempts WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();
  if (attempt) return errorResponse('Already completed today');

  await env.DB.prepare('INSERT INTO crossword_state (user_id, date, grid, elapsed) VALUES (?, ?, ?, ?) ON CONFLICT(user_id, date) DO UPDATE SET grid = ?, elapsed = ?')
    .bind(auth.userId, date, JSON.stringify(grid), elapsed, JSON.stringify(grid), elapsed).run();

  return jsonResponse({ saved: true });
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
