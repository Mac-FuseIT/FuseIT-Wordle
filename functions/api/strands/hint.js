import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';
import { getOrCreateDailyStrand } from '../../../src/strand-selection.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const puzzle = await getOrCreateDailyStrand(env.DB, date);
  if (!puzzle) return errorResponse('No puzzle today', 503);

  let state = await env.DB.prepare('SELECT found_words, hint_charges, hints_used FROM strand_state WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();
  if (!state || state.hint_charges <= 0) return errorResponse('No hint charges available');

  const foundWords = JSON.parse(state.found_words);
  let hintCharges = state.hint_charges - 1;
  const hintsUsed = state.hints_used + 1;

  const foundTargets = new Set(foundWords.filter(f => f.type === 'target').map(f => f.word));
  const unsolved = puzzle.words.find(w => !foundTargets.has(w.word));
  if (!unsolved) return errorResponse('All words found');

  // Count how many times this word has already been hinted
  const prevHints = foundWords.filter(f => f.type === 'hint' && f.word === unsolved.word).length;
  // 0 prev = first hint (cells only), 1 prev = half word, 2+ prev = full word
  const showWord = prevHints >= 1;
  const fullReveal = prevHints >= 2;

  foundWords.push({ word: unsolved.word, type: 'hint', path: unsolved.path });
  await env.DB.prepare('INSERT INTO strand_state (user_id, date, found_words, hint_charges, hints_used) VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id, date) DO UPDATE SET found_words = ?, hint_charges = ?, hints_used = ?')
    .bind(auth.userId, date, JSON.stringify(foundWords), hintCharges, hintsUsed, JSON.stringify(foundWords), hintCharges, hintsUsed).run();

  return jsonResponse({ cells: unsolved.path, word: unsolved.word, showWord, fullReveal, hintCharges });
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
