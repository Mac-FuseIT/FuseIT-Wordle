import { requireAuth, errorResponse } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  // Get all users for the player list
  const users = await env.DB.prepare(
    'SELECT id, nickname, name, email FROM users WHERE id != ? ORDER BY nickname ASC'
  ).bind(auth.userId).all();

  // Get pending challenges for this user
  const challenges = await env.DB.prepare(
    `SELECT * FROM chess_pvp_challenges WHERE (opponent_id = ? OR challenger_id = ?) AND status = 'pending' ORDER BY created_at DESC`
  ).bind(auth.userId, auth.userId).all();

  // Get active games
  const active = await env.DB.prepare(
    `SELECT * FROM chess_pvp_challenges WHERE (opponent_id = ? OR challenger_id = ?) AND status = 'active' ORDER BY created_at DESC`
  ).bind(auth.userId, auth.userId).all();

  return new Response(JSON.stringify({
    users: (users.results || []).map(u => ({ id: u.id, name: u.nickname || u.name, email: u.email })),
    challenges: challenges.results || [],
    active: active.results || [],
  }), { headers: { 'Content-Type': 'application/json' } });
}
