import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';
import { getOrCreateDailyStrand } from '../../../src/strand-selection.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const puzzle = await getOrCreateDailyStrand(env.DB, date);

  const state = await env.DB.prepare('SELECT found_words, hint_charges, hints_used FROM strand_state WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();
  const attempt = await env.DB.prepare('SELECT completed FROM strand_attempts WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();

  return jsonResponse({
    date,
    grid: puzzle.grid,
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
