import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestPost({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;

  // Get user's nickname
  const user = await env.DB.prepare('SELECT nickname, name FROM users WHERE id = ?').bind(userId).first();
  const creatorName = user?.nickname || user?.name || 'Player';

  const today = getToday();

  // Ensure player has a blackjack session for today
  let row = await env.DB.prepare(
    'SELECT session_state FROM blackjack_sessions WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  if (!row) {
    const defaultSession = {
      balance: 100,
      deck: [],
      playerHand: [],
      dealerHand: [],
      currentBet: 0,
      handsPlayed: 0,
      handsWon: 0,
      blackjacks: 0,
      gameOver: false,
    };
    await env.DB.prepare(
      'INSERT INTO blackjack_sessions (user_id, date, session_state) VALUES (?, ?, ?)'
    ).bind(userId, today, JSON.stringify(defaultSession)).run();
  }

  // Generate game ID
  const gameId = crypto.randomUUID();

  // Insert into blackjack_mp_games
  await env.DB.prepare(
    'INSERT INTO blackjack_mp_games (id, creator_id, creator_name, status, player_count, max_players, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
  ).bind(gameId, userId, creatorName, 'waiting', 1, 4, new Date().toISOString()).run();

  return jsonResponse({ gameId, status: 'waiting' });
}
