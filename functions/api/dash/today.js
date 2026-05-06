export async function onRequestGet({ env }) {
  const today = new Date().toISOString().slice(0, 10);
  const row = await env.DB.prepare('SELECT level_data FROM dash_levels WHERE date = ?').bind(today).first();
  if (!row) return new Response(JSON.stringify({ error: 'No level for today' }), { status: 404, headers: { 'Content-Type': 'application/json' } });
  return new Response(JSON.stringify({ date: today, level: JSON.parse(row.level_data) }), {
    headers: { 'Content-Type': 'application/json' },
  });
}
