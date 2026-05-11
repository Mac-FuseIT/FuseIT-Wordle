import { requireAuth, errorResponse } from '../../../src/db.js';

const MAX_POINTS_PER_SECOND = 150;

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { sessionToken, score, level } = await request.json();
  if (!sessionToken || score == null || level == null) return errorResponse('Missing fields', 400);

  const session = await env.DB.prepare(
    'SELECT validated_score, validated_level, last_updated_at, checkpoint_count FROM invade_sessions WHERE session_token = ? AND user_id = ?'
  ).bind(sessionToken, auth.userId).first();

  if (!session) return errorResponse('Invalid session', 403);

  // Must have sent at least one checkpoint — prevents submitting without playing
  if (session.checkpoint_count < 1) return errorResponse('No checkpoints recorded', 403);

  // Validate final delta from last checkpoint
  const elapsed = (Date.now() - new Date(session.last_updated_at).getTime()) / 1000;
  const delta = score - session.validated_score;

  if (delta < 0) return errorResponse('Score cannot decrease', 403);
  if (level < session.validated_level) return errorResponse('Level cannot decrease', 403);
  if (delta > Math.ceil(elapsed * MAX_POINTS_PER_SECOND)) return errorResponse('Score delta not achievable', 403);

  await env.DB.prepare('DELETE FROM invade_sessions WHERE session_token = ?').bind(sessionToken).run();

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
