import { requireAuth, errorResponse } from '../../../src/db.js';
import { getToday } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  const date = getToday();
  const { won, moves, redosUsed, moveHistory, fen, mode } = await request.json();

  if (typeof won !== 'boolean' || typeof moves !== 'number') {
    return errorResponse('Missing fields', 400);
  }

  const gameMode = mode === 'amateur' ? 'amateur' : 'expert';

  const existing = await env.DB.prepare(
    'SELECT id FROM chess_games WHERE user_id = ? AND date = ? AND mode = ?'
  ).bind(auth.userId, date, gameMode).first();
  if (existing) return errorResponse('Already played today', 403);

  // Validate: move count must match moveHistory length (player moves only)
  if (Array.isArray(moveHistory)) {
    const playerMoves = moveHistory.filter((_, i) => i % 2 === 0).length;
    if (playerMoves !== moves) {
      return errorResponse('Move count mismatch', 403);
    }
  }

  // Get the bot level for this mode
  let botLevel;
  if (gameMode === 'amateur') {
    botLevel = getDailyAmateurElo(date);
  } else {
    botLevel = getDailyBotLevel(date);
  }

  await env.DB.prepare(
    `INSERT INTO chess_games (user_id, date, bot_level, won, moves, redos_used, completed_at, mode)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    auth.userId, date,
    botLevel,
    won ? 1 : 0, moves, redosUsed || 0,
    new Date().toISOString(),
    gameMode
  ).run();

  // Clean up session
  await env.DB.prepare(
    'DELETE FROM chess_sessions WHERE user_id = ? AND date = ? AND mode = ?'
  ).bind(auth.userId, date, gameMode).run();

  return new Response(JSON.stringify({ success: true }), {
    headers: { 'Content-Type': 'application/json' }
  });
}

function seededHash(seed) {
  let h = 0xdeadbeef;
  for (let i = 0; i < seed.length; i++) {
    h = Math.imul(h ^ seed.charCodeAt(i), 2654435761);
    h = (h << 13) | (h >>> 19);
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507);
  h = (h ^ (h >>> 16)) >>> 0;
  return h;
}

function getDailyBotLevel(dateStr) {
  const h = seededHash('chess:' + dateStr);
  const weights = [20, 18, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 3, 2, 2, 1, 1];
  const totalWeight = weights.reduce((a, b) => a + b, 0);
  let roll = h % totalWeight;
  let skillLevel = 0;
  for (let i = 0; i < weights.length; i++) {
    roll -= weights[i];
    if (roll < 0) {
      skillLevel = i;
      break;
    }
  }
  return skillLevel;
}

function getDailyAmateurElo(dateStr) {
  const h = seededHash('chess-amateur:' + dateStr);
  const levels = [100, 200, 300, 400, 500, 600, 700, 800, 900];
  const weights = [15, 14, 13, 12, 10, 8, 6, 4, 2];
  const totalWeight = weights.reduce((a, b) => a + b, 0);
  let roll = h % totalWeight;
  let elo = levels[0];
  for (let i = 0; i < weights.length; i++) {
    roll -= weights[i];
    if (roll < 0) {
      elo = levels[i];
      break;
    }
  }
  return elo;
}
