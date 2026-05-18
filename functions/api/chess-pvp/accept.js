import { requireAuth, errorResponse } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { challengeId } = await request.json();
  if (!challengeId) return errorResponse('Missing challengeId', 400);

  const challenge = await env.DB.prepare(
    `SELECT * FROM chess_pvp_challenges WHERE id = ? AND opponent_id = ? AND status = 'pending'`
  ).bind(challengeId, auth.userId).first();

  if (!challenge) return errorResponse('Challenge not found', 404);

  // Use challengeId as the session ID — the DO worker will create the session on first connect
  const sessionId = challengeId;

  await env.DB.prepare(
    `UPDATE chess_pvp_challenges SET status = 'active', session_id = ? WHERE id = ?`
  ).bind(sessionId, challengeId).run();

  return new Response(JSON.stringify({ sessionId, challengeId }), {
    headers: { 'Content-Type': 'application/json' }
  });
}
