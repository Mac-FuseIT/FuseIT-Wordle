import { jsonResponse, errorResponse } from '../../src/db.js';

export async function onRequestPost({ request, env }) {
  try {
    const { name } = await request.json();
    const trimmed = (name || '').trim().toLowerCase();
    if (!trimmed || trimmed.length > 20) return errorResponse('Name must be 1-20 characters');

    await env.DB.prepare('INSERT OR IGNORE INTO users (name) VALUES (?)').bind(trimmed).run();
    const user = await env.DB.prepare('SELECT id, name FROM users WHERE name = ?').bind(trimmed).first();
    return jsonResponse({ userId: user.id, name: user.name });
  } catch (e) {
    return errorResponse('Server error: ' + e.message, 500);
  }
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    },
  });
}
