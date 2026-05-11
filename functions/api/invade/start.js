import { requireAuth, errorResponse } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const sessionToken = crypto.randomUUID();
  await env.DB.prepare(
    'INSERT INTO invade_sessions (user_id, session_token, started_at, last_updated_at, validated_score, validated_level, checkpoint_count) VALUES (?, ?, ?, ?, 0, 1, 0)'
  ).bind(auth.userId, sessionToken, new Date().toISOString(), new Date().toISOString()).run();

  return new Response(JSON.stringify({ sessionToken }), { headers: { 'Content-Type': 'application/json' } });
}
