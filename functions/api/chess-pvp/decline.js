import { requireAuth, errorResponse } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { challengeId } = await request.json();
  if (!challengeId) return errorResponse('Missing challengeId', 400);

  await env.DB.prepare(
    `DELETE FROM chess_pvp_challenges WHERE id = ? AND (challenger_id = ? OR opponent_id = ?) AND status = 'pending'`
  ).bind(challengeId, auth.userId, auth.userId).run();

  return new Response(JSON.stringify({ success: true }), { headers: { 'Content-Type': 'application/json' } });
}
