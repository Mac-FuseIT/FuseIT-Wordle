import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';
import { getOrCreateDailyStrand } from '../../../src/strand-selection.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const puzzle = await getOrCreateDailyStrand(env.DB, date);

  let state = await env.DB.prepare('SELECT found_words, hint_charges, hints_used FROM strand_state WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();
  if (!state || state.hint_charges <= 0) return errorResponse('No hint charges available');

  let hintCharges = state.hint_charges;
  let hintsUsed = state.hints_used;
  const foundWords = JSON.parse(state.found_words);

  const foundTargets = new Set(foundWords.filter(f => f.type === 'target').map(f => f.word));
  const hintedL1 = new Set(foundWords.filter(f => f.type === 'hint_l1').map(f => f.word));
  const hintedL2 = new Set(foundWords.filter(f => f.type === 'hint_l2').map(f => f.word));

  const unsolved = puzzle.words.find(w => !foundTargets.has(w.word));
  if (!unsolved) return errorResponse('All words found');

  if (hintedL1.has(unsolved.word) && !hintedL2.has(unsolved.word)) {
    hintCharges--; hintsUsed++;
    foundWords.push({ word: unsolved.word, type: 'hint_l2' });
    await saveState(env.DB, auth.userId, date, foundWords, hintCharges, hintsUsed);
    return jsonResponse({ level: 2, word: unsolved.word, path: unsolved.path, hintCharges });
  } else if (!hintedL1.has(unsolved.word)) {
    hintCharges--; hintsUsed++;
    foundWords.push({ word: unsolved.word, type: 'hint_l1' });
    await saveState(env.DB, auth.userId, date, foundWords, hintCharges, hintsUsed);
    const letters = [...unsolved.word].sort(() => 0.5 - Math.random());
    return jsonResponse({ level: 1, letters, cells: unsolved.path, hintCharges });
  }

  return errorResponse('No more hints for this word');
}

async function saveState(db, userId, date, foundWords, hintCharges, hintsUsed) {
  await db.prepare('INSERT INTO strand_state (user_id, date, found_words, hint_charges, hints_used) VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id, date) DO UPDATE SET found_words = ?, hint_charges = ?, hints_used = ?')
    .bind(userId, date, JSON.stringify(foundWords), hintCharges, hintsUsed, JSON.stringify(foundWords), hintCharges, hintsUsed).run();
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
