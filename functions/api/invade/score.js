import { requireAuth, errorResponse } from '../../../src/db.js';

const MAX_POINTS_PER_SECOND = 150;

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { score, level, sessionToken } = await request.json();
  if (!score || !sessionToken) return errorResponse('Missing fields', 400);

  const session = await env.DB.prepare(
    'SELECT started_at FROM invade_sessions WHERE session_token = ? AND user_id = ?'
  ).bind(sessionToken, auth.userId).first();

  if (!session) return errorResponse('Invalid session', 403);

  await env.DB.prepare('DELETE FROM invade_sessions WHERE session_token = ?').bind(sessionToken).run();

  const elapsedSeconds = (Date.now() - new Date(session.started_at).getTime()) / 1000;
  if (score > Math.ceil(elapsedSeconds * MAX_POINTS_PER_SECOND)) return errorResponse('Score not achievable', 403);

  const userId = auth.userId;
  const existing = await env.DB.prepare('SELECT score FROM invade_scores WHERE user_id = ?').bind(userId).first();
  if (!existing || score > existing.score) {
    await env.DB.prepare(
      `INSERT INTO invade_scores (user_id, score, level_reached, achieved_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET score = ?, level_reached = ?, achieved_at = ?`
    ).bind(userId, score, level, new Date().toISOString(), score, level, new Date().toISOString()).run();
  }

  return new Response(JSON.stringify({ success: true }), { headers: { 'Content-Type': 'application/json' } });
}
