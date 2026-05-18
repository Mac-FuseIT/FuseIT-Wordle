import { requireAuth } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);

  const top = await env.DB.prepare(`
    SELECT winner_name as name, COUNT(*) as wins
    FROM chess_pvp_results
    GROUP BY winner_id
    ORDER BY wins DESC
    LIMIT 20
  `).all();

  let myRecord = null;
  if (auth) {
    const wins = await env.DB.prepare('SELECT COUNT(*) as c FROM chess_pvp_results WHERE winner_id = ?').bind(auth.userId).first();
    const losses = await env.DB.prepare('SELECT COUNT(*) as c FROM chess_pvp_results WHERE loser_id = ?').bind(auth.userId).first();
    myRecord = { wins: wins?.c ?? 0, losses: losses?.c ?? 0 };
  }

  return new Response(JSON.stringify({
    leaderboard: top.results || [],
    myRecord,
  }), { headers: { 'Content-Type': 'application/json' } });
}
