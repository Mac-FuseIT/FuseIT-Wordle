import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';
import { getOrCreateDailyStrand } from '../../../src/strand-selection.js';

function isAdjacent(a, b) {
  return Math.abs(a[0] - b[0]) <= 1 && Math.abs(a[1] - b[1]) <= 1 && !(a[0] === b[0] && a[1] === b[1]);
}

function isValidPath(path) {
  if (path.length < 3) return false;
  const seen = new Set();
  for (let i = 0; i < path.length; i++) {
    const key = `${path[i][0]}:${path[i][1]}`;
    if (seen.has(key)) return false;
    seen.add(key);
    if (i > 0 && !isAdjacent(path[i - 1], path[i])) return false;
  }
  return true;
}

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { path } = await request.json();
  if (!path || !isValidPath(path)) return jsonResponse({ type: 'invalid' });

  const date = getToday();
  const puzzle = await getOrCreateDailyStrand(env.DB, date);

  const word = path.map(([r, c]) => puzzle.grid[r][c]).join('');

  let state = await env.DB.prepare('SELECT found_words, hint_charges, hints_used FROM strand_state WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();
  const foundWords = state ? JSON.parse(state.found_words) : [];
  let hintCharges = state ? state.hint_charges : 0;
  const hintsUsed = state ? state.hints_used : 0;

  if (foundWords.some(f => f.word === word && f.type === 'target')) return jsonResponse({ type: 'already_found' });

  // Check if it's a target word
  const targetMatch = puzzle.words.find(w => w.word === word);
  if (targetMatch) {
    foundWords.push({ word, type: 'target', path });
    await saveState(env.DB, auth.userId, date, foundWords, hintCharges, hintsUsed);
    const completed = foundWords.filter(f => f.type === 'target').length === puzzle.words.length;
    if (completed) {
      await env.DB.prepare('INSERT OR IGNORE INTO strand_attempts (user_id, date, hints_used, completed, completed_at) VALUES (?, ?, ?, 1, ?)')
        .bind(auth.userId, date, hintsUsed, new Date().toISOString()).run();
    }
    return jsonResponse({ type: 'target', word, completed, found: foundWords.filter(f => f.type === 'target').length, total: puzzle.words.length });
  }

  // Check non-theme valid word (4+ letters)
  if (word.length >= 4 && !foundWords.some(f => f.word === word)) {
    try {
      const dictRes = await fetch(`https://api.dictionaryapi.dev/api/v2/entries/en/${word.toLowerCase()}`);
      if (dictRes.ok) {
        foundWords.push({ word, type: 'bonus', path });
        const bonusCount = foundWords.filter(f => f.type === 'bonus').length;
        hintCharges = Math.floor(bonusCount / 3);
        await saveState(env.DB, auth.userId, date, foundWords, hintCharges, hintsUsed);
        return jsonResponse({ type: 'bonus', word, hintCharges, bonusCount });
      }
    } catch (_) {}
  }

  return jsonResponse({ type: 'invalid' });
}

async function saveState(db, userId, date, foundWords, hintCharges, hintsUsed) {
  await db.prepare('INSERT INTO strand_state (user_id, date, found_words, hint_charges, hints_used) VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id, date) DO UPDATE SET found_words = ?, hint_charges = ?, hints_used = ?')
    .bind(userId, date, JSON.stringify(foundWords), hintCharges, hintsUsed, JSON.stringify(foundWords), hintCharges, hintsUsed).run();
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
