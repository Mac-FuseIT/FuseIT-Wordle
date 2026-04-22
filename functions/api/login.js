import { jsonResponse, errorResponse } from '../../src/db.js';
import { hashPassword } from '../../src/auth.js';

export async function onRequestPost({ request, env }) {
  try {
    const { email, password } = await request.json();
    const trimmed = (email || '').trim().toLowerCase();

    if (!trimmed || !trimmed.endsWith('@gofuseit.com')) {
      return errorResponse('Naha, you are not allowed to touch!!');
    }
    if (!password) return errorResponse('Password is required');

    const user = await env.DB.prepare(
      'SELECT id, name, nickname, password, theme FROM users WHERE email = ?'
    ).bind(trimmed).first();

    if (!user) return errorResponse('Account not found. Register first.');

    const hashed = await hashPassword(password.trim());
    if (user.password !== hashed) return errorResponse('Wrong password');

    return jsonResponse({ userId: user.id, name: user.nickname || user.name, email: trimmed, theme: user.theme ? JSON.parse(user.theme) : null });
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
