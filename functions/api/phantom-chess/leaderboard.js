import { requireAuth } from '../../../src/db.js';
import { getToday } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  const date = getToday();

  const top = await env.DB.prepare(`
    SELECT u.nickname, u.name, g.won, g.moves, g.bot_level, g.date
    FROM phantom_chess_games g JOIN users u ON u.id = g.user_id
    WHERE g.date = ?
    ORDER BY g.won DESC, g.moves ASC
    LIMIT 30
  `).bind(date).all();

  const monthly = await env.DB.prepare(`
    SELECT u.nickname, u.name,
      SUM(CASE WHEN g.won = 1 THEN 1 ELSE 0 END) as wins,
      COUNT(*) as games,
      AVG(CASE WHEN g.won = 1 THEN g.moves ELSE NULL END) as avg_moves
    FROM phantom_chess_games g JOIN users u ON u.id = g.user_id
    WHERE g.date >= date('now', 'start of month')
    GROUP BY g.user_id
    ORDER BY wins DESC, avg_moves ASC
    LIMIT 20
  `).all();

  let myHistory = [];
  if (auth) {
    const rows = await env.DB.prepare(
      'SELECT date, won, moves, bot_level FROM phantom_chess_games WHERE user_id = ? ORDER BY date DESC LIMIT 10'
    ).bind(auth.userId).all();
    myHistory = rows.results || [];
  }

  return new Response(JSON.stringify({
    daily: (top.results || []).map(r => ({ nickname: r.nickname || r.name, won: !!r.won, moves: r.moves, botLevel: r.bot_level })),
    monthly: (monthly.results || []).map(r => ({ nickname: r.nickname || r.name, wins: r.wins, games: r.games, avgMoves: r.avg_moves ? Math.round(r.avg_moves) : null })),
    history: myHistory,
  }), { headers: { 'Content-Type': 'application/json' } });
}
