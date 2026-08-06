import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';
import { getOrCreateChainItPuzzle } from '../../../src/chainit-selection.js';

function countDifferences(word1, word2) {
  let diffs = 0;
  for (let i = 0; i < word1.length; i++) {
    if (word1[i] !== word2[i]) diffs++;
  }
  return diffs;
}

function colorGuess(guess, targetWord) {
  const result = Array(targetWord.length).fill(null);
  const targetChars = [...targetWord];
  const guessChars = [...guess];

  // First pass: greens (correct position)
  for (let i = 0; i < guessChars.length; i++) {
    if (guessChars[i] === targetChars[i]) {
      result[i] = { letter: guessChars[i], status: 'correct' };
      targetChars[i] = null;
      guessChars[i] = null;
    }
  }

  // Second pass: yellows (in target but wrong position)
  for (let i = 0; i < guessChars.length; i++) {
    if (guessChars[i] === null) continue;
    const idx = targetChars.indexOf(guessChars[i]);
    if (idx !== -1) {
      result[i] = { letter: guessChars[i], status: 'present' };
      targetChars[idx] = null;
    } else {
      result[i] = { letter: guessChars[i], status: 'absent' };
    }
  }

  return result;
}

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;
  const date = getToday();

  const body = await request.json();
  const guess = (body.guess || '').toLowerCase().trim();

  // Get puzzle
  const puzzle = await getOrCreateChainItPuzzle(env.DB, date);
  if (!puzzle) return errorResponse('No puzzle available', 500);

  const targetWord = puzzle.target_word;
  const startWord = puzzle.start_word;
  const length = puzzle.length;

  // Check if already completed
  const attempt = await env.DB.prepare(
    'SELECT id FROM chainit_attempts WHERE user_id = ? AND date = ?'
  ).bind(userId, date).first();
  if (attempt) return errorResponse('Already completed today');

  // Validate length
  if (guess.length !== length) {
    return errorResponse(`Guess must be ${length} letters`);
  }

  // Get current state
  const stateRow = await env.DB.prepare(
    'SELECT guesses FROM chainit_state WHERE user_id = ? AND date = ?'
  ).bind(userId, date).first();
  const guesses = stateRow ? JSON.parse(stateRow.guesses) : [];

  // Determine previous word (start word if no guesses yet)
  const previousWord = guesses.length === 0 ? startWord : guesses[guesses.length - 1];

  // Validate exactly 1 letter changed
  if (countDifferences(previousWord, guess) !== 1) {
    return errorResponse('Must change exactly 1 letter from previous word');
  }

  // Dictionary validation (skip if guess matches target — it was pre-validated)
  if (guess !== targetWord) {
    let dictOk = false;
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const dictRes = await fetch(`https://api.dictionaryapi.dev/api/v2/entries/en/${guess}`);
        if (dictRes.ok) { dictOk = true; break; }
        if (dictRes.status === 404) break;
      } catch (_) {
        if (attempt < 2) await new Promise(r => setTimeout(r, 500));
      }
    }
    if (!dictOk) return errorResponse('Not a valid word');
  }

  // Valid guess — add to chain
  guesses.push(guess);

  // Check if solved
  const solved = guess === targetWord;

  if (solved) {
    // Persist to attempts table (permanent record)
    await env.DB.prepare(
      'INSERT OR IGNORE INTO chainit_attempts (user_id, date, guesses, steps, completed_at) VALUES (?, ?, ?, ?, ?)'
    ).bind(userId, date, JSON.stringify(guesses), guesses.length, new Date().toISOString()).run();

    // Clear in-progress state
    await env.DB.prepare(
      'DELETE FROM chainit_state WHERE user_id = ? AND date = ?'
    ).bind(userId, date).run();
  } else {
    // Persist in-progress state
    await env.DB.prepare(
      'INSERT INTO chainit_state (user_id, date, guesses) VALUES (?, ?, ?) ON CONFLICT(user_id, date) DO UPDATE SET guesses = ?'
    ).bind(userId, date, JSON.stringify(guesses), JSON.stringify(guesses)).run();
  }

  // Color the guess relative to the target word
  const result = colorGuess(guess, targetWord);

  return jsonResponse({
    valid: true,
    solved,
    guess,
    result,
    steps: guesses.length,
    guesses,
  });
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}
