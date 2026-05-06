export async function onRequestPost({ request, env }) {
  const { userId, nickname, score, level } = await request.json();
  if (!userId || !score) return new Response(JSON.stringify({ error: 'Missing fields' }), { status: 400 });

  const existing = await env.DB.prepare('SELECT score FROM invade_scores WHERE user_id = ?').bind(userId).first();
  if (!existing || score > existing.score) {
    await env.DB.prepare(
      `INSERT INTO invade_scores (user_id, nickname, score, level_reached, achieved_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET score = ?, level_reached = ?, nickname = ?, achieved_at = ?`
    ).bind(userId, nickname, score, level, new Date().toISOString(), score, level, nickname, new Date().toISOString()).run();
  }

  return new Response(JSON.stringify({ success: true }), { headers: { 'Content-Type': 'application/json' } });
}
