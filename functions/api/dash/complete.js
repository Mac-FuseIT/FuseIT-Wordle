export async function onRequestPost({ request, env }) {
  const { userId, nickname, score, timeSeconds, coins } = await request.json();
  if (!userId || !nickname || score == null) {
    return new Response(JSON.stringify({ error: 'Missing fields' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
  }
  const today = new Date().toISOString().slice(0, 10);
  const completedAt = new Date().toISOString();
  try {
    await env.DB.prepare(
      'INSERT INTO dash_scores (user_id, date, nickname, score, time_seconds, coins, completed_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, date) DO UPDATE SET score = MAX(score, excluded.score), time_seconds = CASE WHEN excluded.score > score THEN excluded.time_seconds ELSE time_seconds END, coins = CASE WHEN excluded.score > score THEN excluded.coins ELSE coins END, completed_at = CASE WHEN excluded.score > score THEN excluded.completed_at ELSE completed_at END'
    ).bind(userId, today, nickname, score, timeSeconds ?? 0, coins ?? 0, completedAt).run();
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
  return new Response(JSON.stringify({ ok: true }), { headers: { 'Content-Type': 'application/json' } });
}
