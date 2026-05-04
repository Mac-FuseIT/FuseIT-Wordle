import { jsonResponse } from '../../../src/db.js';

export async function onRequestGet({ env }) {
  const sessions = await env.DB.prepare(
    'SELECT session_id, creator_name FROM pong_sessions WHERE created_at > datetime("now", "-1 hour") ORDER BY created_at DESC'
  ).all();
  
  return jsonResponse({ sessions: sessions.results || [] });
}
