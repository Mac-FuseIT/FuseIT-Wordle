import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';
import { getOrCreateDailyPuzzle } from '../../../src/crossword-selection.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const puzzle = await getOrCreateDailyPuzzle(env.DB, date);
  return jsonResponse({ grid: puzzle.grid });
}

export async function onRequestOptions() {
  return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' } });
}
