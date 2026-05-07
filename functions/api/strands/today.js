import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const row = await env.DB.prepare('SELECT grid, theme, spangram, theme_words FROM spanit_puzzles WHERE date = ?').bind(date).first();
  if (!row) return errorResponse("Today's puzzle isn't ready yet. Check back soon!", 503);

  const puzzle = { grid: JSON.parse(row.grid), words: JSON.parse(row.theme_words), theme: row.theme, spangram: row.spangram };

  const state = await env.DB.prepare('SELECT found_words, hint_charges, hints_used FROM spanit_state WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();
  const attempt = await env.DB.prepare('SELECT completed FROM spanit_attempts WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();

  return jsonResponse({
    date,
    grid: puzzle.grid,
    theme: puzzle.theme,
    spangram: puzzle.spangram,
    wordCount: puzzle.words.length,
    foundWords: state ? JSON.parse(state.found_words) : [],
    hintCharges: state ? state.hint_charges : 0,
    hintsUsed: state ? state.hints_used : 0,
    completed: !!(attempt && attempt.completed),
  });
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
