import { requireAuth, errorResponse } from '../../../src/db.js';

// Theoretical max: fastest spawn (500ms), all tier-3 (50pts), plus level bonuses.
// Generous ceiling of 150 pts/sec to allow for real play variance.
const MAX_POINTS_PER_SECOND = 150;

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { nickname, score, level, sessionToken } = await request.json();
  if (!score || !sessionToken) return errorResponse('Missing fields', 400);

  const session = await env.DB.prepare(
    'SELECT started_at FROM invade_sessions WHERE session_token = ? AND user_id = ?'
  ).bind(sessionToken, auth.userId).first();

  if (!session) return errorResponse('Invalid session', 403);

  // Always delete the session so it can't be reused
  await env.DB.prepare('DELETE FROM invade_sessions WHERE session_token = ?').bind(sessionToken).run();

  const elapsedSeconds = (Date.now() - new Date(session.started_at).getTime()) / 1000;
  const maxPossibleScore = Math.ceil(elapsedSeconds * MAX_POINTS_PER_SECOND);

  if (score > maxPossibleScore) return errorResponse('Score not achievable', 403);

  const userId = auth.userId;
  const existing = await env.DB.prepare('SELECT score FROM invade_scores WHERE user_id = ?').bind(userId).first();
  if (!existing || score > existing.score) {
    await env.DB.prepare(
      `INSERT INTO invade_scores (user_id, nickname, score, level_reached, achieved_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET score = ?, level_reached = ?, nickname = ?, achieved_at = ?`
    ).bind(userId, nickname, score, level, new Date().toISOString(), score, level, nickname, new Date().toISOString()).run();
  }

  return new Response(JSON.stringify({ success: true }), { headers: { 'Content-Type': 'application/json' } });
}
