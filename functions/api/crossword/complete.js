import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';
import { getOrCreateDailyPuzzle } from '../../../src/crossword-selection.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { grid, elapsed } = await request.json();
  const date = getToday();

  const existing = await env.DB.prepare('SELECT id FROM crossword_attempts WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();
  if (existing) return errorResponse('Already completed today');

  const puzzle = await getOrCreateDailyPuzzle(env.DB, date);

  // Validate grid matches answer
  for (let r = 0; r < puzzle.grid.length; r++) {
    for (let c = 0; c < puzzle.grid[r].length; c++) {
      if (puzzle.grid[r][c] === null) continue;
      if (!grid[r] || (grid[r][c] || '').toUpperCase() !== puzzle.grid[r][c]) {
        return jsonResponse({ correct: false });
      }
    }
  }

  await env.DB.prepare('INSERT INTO crossword_attempts (user_id, date, time_seconds, completed_at) VALUES (?, ?, ?, ?)')
    .bind(auth.userId, date, elapsed, new Date().toISOString()).run();
  await env.DB.prepare('DELETE FROM crossword_state WHERE user_id = ? AND date = ?').bind(auth.userId, date).run();

  return jsonResponse({ correct: true, timeSeconds: elapsed });
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
