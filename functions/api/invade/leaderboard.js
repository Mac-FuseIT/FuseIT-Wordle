import { requireAuth, errorResponse } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);

  const top = await env.DB.prepare(`
    SELECT u.nickname, u.name, s.score, s.level_reached, s.achieved_at
    FROM invade_scores s JOIN users u ON u.id = s.user_id
    ORDER BY s.score DESC LIMIT 20
  `).all();

  const auth = await requireAuth(request, env);
  let best = 0;
  if (auth) {
    const row = await env.DB.prepare('SELECT score FROM invade_scores WHERE user_id = ?').bind(auth.userId).first();
    best = row?.score ?? 0;
  }

  const leaderboard = (top.results || []).map(r => ({
    nickname: r.nickname || r.name,
    score: r.score,
    level_reached: r.level_reached,
    achieved_at: r.achieved_at,
  }));

  return new Response(JSON.stringify({ leaderboard, best }), {
    headers: { 'Content-Type': 'application/json' }
  });
}
