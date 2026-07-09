import { jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const results = await env.DB.prepare(
    "SELECT id, creator_name, status, player_count, max_players, created_at FROM blackjack_mp_games WHERE status != 'finished' ORDER BY created_at DESC"
  ).all();

  return jsonResponse({ games: results.results || [] });
}
