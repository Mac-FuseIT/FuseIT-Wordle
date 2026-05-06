export async function onRequestGet({ env }) {
  const today = new Date().toISOString().slice(0, 10);
  const { results } = await env.DB.prepare(
    'SELECT nickname, score, time_seconds, coins FROM dash_scores WHERE date = ? ORDER BY score DESC, time_seconds ASC LIMIT 20'
  ).bind(today).all();
  return new Response(JSON.stringify({ leaderboard: results }), { headers: { 'Content-Type': 'application/json' } });
}
