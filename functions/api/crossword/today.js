import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';
import { getOrCreateDailyPuzzle } from '../../../src/crossword-selection.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const puzzle = await getOrCreateDailyPuzzle(env.DB, date);

  // Return empty grid (nulls for black cells, empty strings for playable)
  const emptyGrid = puzzle.grid.map(row => row.map(cell => cell === null ? null : ''));

  // Check if user has in-progress state
  const state = await env.DB.prepare('SELECT grid, elapsed, hints_used, checks_used FROM crossword_state WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();
  const attempt = await env.DB.prepare('SELECT time_seconds FROM crossword_attempts WHERE user_id = ? AND date = ?').bind(auth.userId, date).first();

  return jsonResponse({
    date,
    grid: state ? JSON.parse(state.grid) : emptyGrid,
    cluesAcross: puzzle.across,
    cluesDown: puzzle.down,
    elapsed: state ? state.elapsed : 0,
    hintsUsed: state ? state.hints_used : 0,
    checksUsed: state ? state.checks_used : 0,
    completed: !!attempt,
    timeSeconds: attempt ? attempt.time_seconds : null,
  });
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
