import { jsonResponse } from '../../../src/db.js';

export async function onRequestPost({ env, request }) {
  const { nickname } = await request.json();
  const id = env.PONG_GAME.newUniqueId();
  const sessionId = id.toString();
  
  await env.DB.prepare(
    'INSERT INTO pong_sessions (session_id, creator_name, created_at) VALUES (?, ?, ?)'
  ).bind(sessionId, nickname, new Date().toISOString()).run();
  
  // Initialize the Durable Object with the session ID
  const stub = env.PONG_GAME.get(id);
  await stub.fetch('http://internal/init', {
    method: 'POST',
    body: JSON.stringify({ sessionId }),
  });
  
  return jsonResponse({ sessionId });
}
