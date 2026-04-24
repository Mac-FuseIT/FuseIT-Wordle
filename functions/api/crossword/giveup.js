import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const existing = await env.DB.prepare('SELECT id FROM crossword_attempts WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();
  if (existing) return errorResponse('Already completed today');

  // Record as failed with penalty time (600 seconds = 10 min)
  await env.DB.prepare('INSERT INTO crossword_attempts (user_id, date, time_seconds, completed_at) VALUES (?, ?, ?, ?)')
    .bind(auth.userId, date, 600, new Date().toISOString()).run();
  await env.DB.prepare('DELETE FROM crossword_state WHERE user_id = ? AND date = ?').bind(auth.userId, date).run();

  return jsonResponse({ success: true });
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
