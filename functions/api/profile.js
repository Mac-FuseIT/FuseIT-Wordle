import { jsonResponse, errorResponse } from '../../src/db.js';
import { hashPassword } from '../../src/auth.js';

export async function onRequestPost({ request, env }) {
  try {
    const { userId, nickname, newPassword } = await request.json();
    if (!userId) return errorResponse('Missing userId');

    if (nickname !== undefined) {
      const trimmed = (nickname || '').trim();
      if (!trimmed || trimmed.length > 20) return errorResponse('Nickname must be 1-20 characters');
      await env.DB.prepare('UPDATE users SET nickname = ?, name = ? WHERE id = ?').bind(trimmed, trimmed, userId).run();
    }

    if (newPassword !== undefined) {
      const pw = (newPassword || '').trim();
      if (pw.length < 4) return errorResponse('Password must be at least 4 characters');
      const hashed = await hashPassword(pw);
      await env.DB.prepare('UPDATE users SET password = ? WHERE id = ?').bind(hashed, userId).run();
    }

    const user = await env.DB.prepare('SELECT nickname, name FROM users WHERE id = ?').bind(userId).first();
    return jsonResponse({ name: user.nickname || user.name, updated: true });
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
