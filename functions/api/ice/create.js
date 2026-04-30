import { jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { bestOf, puckSpeed, playersPerSide } = await request.json();
  const sessionId = crypto.randomUUID().slice(0, 8).toUpperCase();

  await env.DB.prepare('INSERT INTO ice_sessions (session_id, creator_id, settings, status, created_at) VALUES (?, ?, ?, ?, ?)')
    .bind(sessionId, auth.userId, JSON.stringify({ bestOf, puckSpeed, playersPerSide }), 'waiting', new Date().toISOString()).run();

  // Initialize Durable Object
  const id = env.ICE_GAME.idFromName(sessionId);
  const stub = env.ICE_GAME.get(id);
  await stub.fetch(new Request('https://fake/settings', {
    method: 'POST',
    body: JSON.stringify({ bestOf, puckSpeed, playersPerSide, sessionId }),
  }));

  return jsonResponse({ sessionId });
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
