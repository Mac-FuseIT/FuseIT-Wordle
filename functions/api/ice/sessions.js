import { jsonResponse, requireAuth } from '../../../src/db.js';

export async function onRequestGet({ env }) {
  // Clean up old finished sessions (older than 1 hour)
  await env.DB.prepare("DELETE FROM ice_sessions WHERE status = 'finished' AND datetime(created_at, '+1 hour') < datetime('now')").run();
  
  const sessions = await env.DB.prepare("SELECT session_id, settings, status, created_at FROM ice_sessions WHERE status = 'waiting' ORDER BY created_at DESC LIMIT 20").all();
  return jsonResponse({ sessions: sessions.results.map(s => ({ ...s, settings: JSON.parse(s.settings) })) });
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
