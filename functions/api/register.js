import { jsonResponse, errorResponse } from '../../src/db.js';
import { sendEmail, generatePassword } from '../../src/email.js';
import { hashPassword } from '../../src/auth.js';

export async function onRequestPost({ request, env }) {
  try {
    const { email } = await request.json();
    const trimmed = (email || '').trim().toLowerCase();

    if (!trimmed || !trimmed.endsWith('@gofuseit.com')) {
      return errorResponse('Naha, you are not allowed to touch!!');
    }

    const existing = await env.DB.prepare('SELECT id FROM users WHERE email = ?').bind(trimmed).first();
    if (existing) {
      return errorResponse('Account already exists. Use login or forgot password.');
    }

    const password = generatePassword();
    const hashed = await hashPassword(password);
    const nickname = trimmed.split('@')[0];

    await env.DB.prepare(
      'INSERT INTO users (name, email, nickname, password) VALUES (?, ?, ?, ?)'
    ).bind(nickname, trimmed, nickname, hashed).run();

    try {
      await sendEmail(
        env,
        trimmed,
        'Welcome to Guess.IT!',
        `Welcome to Guess.IT!\n\nYour login details:\nEmail: ${trimmed}\nPassword: ${password}\n\nYou can change your password in your profile after logging in.`
      );
    } catch (emailErr) {
      await env.DB.prepare('DELETE FROM users WHERE email = ?').bind(trimmed).run();
      return errorResponse('Failed to send email: ' + emailErr.message, 500);
    }

    return jsonResponse({ message: 'Account created! Check your email for your password.' });
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
