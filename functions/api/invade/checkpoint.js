import { requireAuth, errorResponse } from '../../../src/db.js';

const MAX_POINTS_PER_SECOND = 150;

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { sessionToken, score, level } = await request.json();
  if (!sessionToken || score == null || level == null) return errorResponse('Missing fields', 400);

  const session = await env.DB.prepare(
    'SELECT validated_score, validated_level, last_updated_at FROM invade_sessions WHERE session_token = ? AND user_id = ?'
  ).bind(sessionToken, auth.userId).first();

  if (!session) return errorResponse('Invalid session', 403);

  const elapsed = (Date.now() - new Date(session.last_updated_at).getTime()) / 1000;
  const delta = score - session.validated_score;

  if (delta < 0) return errorResponse('Score cannot decrease', 403);
  if (level < session.validated_level) return errorResponse('Level cannot decrease', 403);
  if (delta > Math.ceil(elapsed * MAX_POINTS_PER_SECOND)) return errorResponse('Score delta not achievable', 403);

  await env.DB.prepare(
    'UPDATE invade_sessions SET validated_score = ?, validated_level = ?, last_updated_at = ? WHERE session_token = ?'
  ).bind(score, level, new Date().toISOString(), sessionToken).run();

  return new Response(JSON.stringify({ ok: true }), { headers: { 'Content-Type': 'application/json' } });
}
