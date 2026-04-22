import { getToday, jsonResponse, errorResponse, requireAuth } from '../../src/db.js';
import { getOrCreateDailyWord } from '../../src/word-selection.js';

function evaluateGuess(guess, answer) {
  const result = Array(answer.length).fill(null);
  const answerChars = [...answer];
  const guessChars = [...guess];

  for (let i = 0; i < guessChars.length; i++) {
    if (guessChars[i] === answerChars[i]) {
      result[i] = { letter: guessChars[i], status: 'correct' };
      answerChars[i] = null;
      guessChars[i] = null;
    }
  }
  for (let i = 0; i < guessChars.length; i++) {
    if (guessChars[i] === null) continue;
    const idx = answerChars.indexOf(guessChars[i]);
    if (idx !== -1) {
      result[i] = { letter: guessChars[i], status: 'present' };
      answerChars[idx] = null;
    } else {
      result[i] = { letter: guessChars[i], status: 'absent' };
    }
  }
  return result;
}

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const { guess } = await request.json();
  const userId = auth.userId;
  if (!guess) return errorResponse('Missing guess');

  const date = getToday();
  const { word, length } = await getOrCreateDailyWord(env.DB, date);
  const maxAttempts = length + 1;
  const normalizedGuess = guess.trim().toLowerCase();

  if (normalizedGuess.length !== length) return errorResponse(`Guess must be ${length} letters`);

  // Validate word exists via dictionary API
  const dictRes = await fetch(`https://api.dictionaryapi.dev/api/v2/entries/en/${normalizedGuess}`);
  if (!dictRes.ok) return errorResponse('Not a valid word');

  // Check if already completed
  const existing = await env.DB.prepare('SELECT id FROM attempts WHERE user_id = ? AND date = ?').bind(userId, date).first();
  if (existing) return errorResponse('Already completed today');

  // Get or create game state
  let state = await env.DB.prepare('SELECT guesses FROM game_state WHERE user_id = ? AND date = ?').bind(userId, date).first();
  const guesses = state ? JSON.parse(state.guesses) : [];

  if (guesses.length >= maxAttempts) return errorResponse('No attempts remaining');

  const result = evaluateGuess(normalizedGuess, word);
  guesses.push({ guess: normalizedGuess, result });

  const solved = normalizedGuess === word;
  const outOfAttempts = guesses.length >= maxAttempts;

  if (solved || outOfAttempts) {
    // Save final attempt and remove game state
    await env.DB.prepare(
      'INSERT INTO attempts (user_id, date, guesses, num_guesses, solved, completed_at) VALUES (?, ?, ?, ?, ?, ?)'
    ).bind(userId, date, JSON.stringify(guesses), solved ? guesses.length : guesses.length + 3, solved ? 1 : 0, new Date().toISOString()).run();
    await env.DB.prepare('DELETE FROM game_state WHERE user_id = ? AND date = ?').bind(userId, date).run();
  } else {
    // Update game state
    await env.DB.prepare(
      'INSERT INTO game_state (user_id, date, guesses) VALUES (?, ?, ?) ON CONFLICT(user_id, date) DO UPDATE SET guesses = ?'
    ).bind(userId, date, JSON.stringify(guesses), JSON.stringify(guesses)).run();
  }

  return jsonResponse({
    result,
    solved,
    attemptsUsed: guesses.length,
    maxAttempts,
    guesses,
    ...(solved || outOfAttempts ? { answer: word } : {}),
  });
}

// Resume game state
export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;

  const date = getToday();
  const { length } = await getOrCreateDailyWord(env.DB, date);
  const maxAttempts = length + 1;

  // Check if already completed
  const attempt = await env.DB.prepare('SELECT num_guesses, solved, guesses FROM attempts WHERE user_id = ? AND date = ?').bind(userId, date).first();
  if (attempt) {
    return jsonResponse({
      completed: true,
      solved: !!attempt.solved,
      attemptsUsed: attempt.num_guesses,
      maxAttempts,
      guesses: JSON.parse(attempt.guesses || '[]'),
    });
  }

  const state = await env.DB.prepare('SELECT guesses FROM game_state WHERE user_id = ? AND date = ?').bind(userId, date).first();
  return jsonResponse({
    completed: false,
    attemptsUsed: state ? JSON.parse(state.guesses).length : 0,
    maxAttempts,
    guesses: state ? JSON.parse(state.guesses) : [],
  });
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}
