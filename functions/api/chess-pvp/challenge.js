import { requireAuth, errorResponse } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { opponentId, colorChoice, timeControl } = await request.json();
  if (!opponentId || !colorChoice || !timeControl) return errorResponse('Missing fields', 400);

  const id = crypto.randomUUID();

  // Get opponent name
  const opponent = await env.DB.prepare('SELECT nickname, name FROM users WHERE id = ?').bind(opponentId).first();
  if (!opponent) return errorResponse('Opponent not found', 404);

  // Get challenger name
  const challenger = await env.DB.prepare('SELECT nickname, name FROM users WHERE id = ?').bind(auth.userId).first();

  await env.DB.prepare(
    `INSERT INTO chess_pvp_challenges (id, challenger_id, challenger_name, opponent_id, opponent_name, color_choice, time_control, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)`
  ).bind(id, auth.userId, challenger.nickname || challenger.name, opponentId, opponent.nickname || opponent.name, colorChoice, timeControl, new Date().toISOString()).run();

  return new Response(JSON.stringify({ challengeId: id }), { headers: { 'Content-Type': 'application/json' } });
}
