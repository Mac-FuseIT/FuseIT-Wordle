import { verifyToken } from './auth.js';

export function getToday() {
  return getGameDate(new Date());
}

// Returns the active game date — weekends use Friday's date
export function getGameDate(date) {
  const day = date.getUTCDay(); // 0=Sun, 6=Sat
  if (day === 0) date.setUTCDate(date.getUTCDate() - 2); // Sun → Fri
  else if (day === 6) date.setUTCDate(date.getUTCDate() - 1); // Sat → Fri
  return date.toISOString().split('T')[0];
}

export function isValidDate(dateStr) {
  return typeof dateStr === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(dateStr) && !isNaN(Date.parse(dateStr));
}

export function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });
}

export function errorResponse(message, status = 400) {
  return jsonResponse({ error: message }, status);
}

export async function requireAuth(request, env) {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null;
  const token = authHeader.slice(7);
  return verifyToken(token, env.TOKEN_SECRET);
}
