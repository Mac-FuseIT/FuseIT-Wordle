export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const userId = url.searchParams.get('userId');

  const top = await env.DB.prepare(
    'SELECT nickname, score, level_reached, achieved_at FROM invade_scores ORDER BY score DESC LIMIT 20'
  ).all();

  let best = 0;
  if (userId) {
    const row = await env.DB.prepare('SELECT score FROM invade_scores WHERE user_id = ?').bind(userId).first();
    best = row?.score ?? 0;
  }

  return new Response(JSON.stringify({ leaderboard: top.results || [], best }), {
    headers: { 'Content-Type': 'application/json' }
  });
}
