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

    const user = await env.DB.prepare('SELECT id FROM users WHERE email = ?').bind(trimmed).first();
    if (!user) return errorResponse('Account not found. Register first.');

    const password = generatePassword();
    const hashed = await hashPassword(password);
    await env.DB.prepare('UPDATE users SET password = ? WHERE id = ?').bind(hashed, user.id).run();

    const sent = await sendEmail(
      env.RESEND_API_KEY,
      trimmed,
      'Guess.IT — New Password',
      `Your new Guess.IT password is: ${password}\n\nYou can change it in your profile after logging in.`
    );

    if (!sent) return errorResponse('Failed to send email. Try again.', 500);

    return jsonResponse({ message: 'New password sent to your email!' });
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
