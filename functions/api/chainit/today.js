import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';
import { getOrCreateChainItPuzzle } from '../../../src/chainit-selection.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;
  const date = getToday();

  // Get or create today's puzzle
  const puzzle = await getOrCreateChainItPuzzle(env.DB, date);
  if (!puzzle) return errorResponse('No puzzle available', 500);

  // Check if already completed
  const attempt = await env.DB.prepare(
    'SELECT steps, guesses FROM chainit_attempts WHERE user_id = ? AND date = ?'
  ).bind(userId, date).first();

  if (attempt) {
    return jsonResponse({
      date,
      puzzleNumber: getPuzzleNumber(date),
      startWord: puzzle.start_word,
      targetWord: puzzle.target_word,
      length: puzzle.length,
      completed: true,
      steps: attempt.steps,
      guesses: JSON.parse(attempt.guesses),
    });
  }

  // Check for in-progress state
  const state = await env.DB.prepare(
    'SELECT guesses FROM chainit_state WHERE user_id = ? AND date = ?'
  ).bind(userId, date).first();

  return jsonResponse({
    date,
    puzzleNumber: getPuzzleNumber(date),
    startWord: puzzle.start_word,
    targetWord: puzzle.target_word,
    length: puzzle.length,
    completed: false,
    guesses: state ? JSON.parse(state.guesses) : [],
  });
}

function getPuzzleNumber(dateStr) {
  const epoch = new Date('2026-08-06');
  const today = new Date(dateStr);
  return Math.floor((today - epoch) / 86400000) + 1;
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}
