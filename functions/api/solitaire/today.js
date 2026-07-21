import { getToday, jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';
import { dealGame } from '../../../src/solitaire-deck.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);
  const userId = auth.userId;
  const today = getToday();

  // Check if already completed
  const resultRow = await env.DB.prepare(
    'SELECT * FROM solitaire_results WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  if (resultRow) {
    return jsonResponse({
      status: resultRow.completed ? 'won' : 'gave_up',
      points: resultRow.points,
      moves: resultRow.moves,
      time_seconds: resultRow.time_seconds,
      completed: !!resultRow.completed,
    });
  }

  // Get or create session
  let row = await env.DB.prepare(
    'SELECT session_state, started_at FROM solitaire_sessions WHERE user_id = ? AND date = ?'
  ).bind(userId, today).first();

  let state;
  let startedAt = null;
  if (!row) {
    state = dealGame(today);
    await env.DB.prepare(
      'INSERT INTO solitaire_sessions (user_id, date, session_state) VALUES (?, ?, ?)'
    ).bind(userId, today, JSON.stringify(state)).run();
  } else {
    state = JSON.parse(row.session_state);
    startedAt = row.started_at;
  }

  // Return sanitized state (hide hidden cards)
  const elapsed = startedAt ? Math.floor((Date.now() - new Date(startedAt).getTime()) / 1000) : 0;

  return jsonResponse({
    status: state.status,
    stock_count: state.stock.length,
    waste_top: state.waste.length > 0 ? state.waste.slice(-3) : [],
    waste_count: state.waste.length,
    reserve: state.reserve || null,
    foundations: {
      hearts: state.foundations.hearts.length,
      diamonds: state.foundations.diamonds.length,
      clubs: state.foundations.clubs.length,
      spades: state.foundations.spades.length,
    },
    tableau: state.tableau.map(col => ({
      hidden: col.hidden.length,
      visible: col.visible,
    })),
    moves: state.moves,
    elapsed_seconds: elapsed,
    started: !!startedAt,
  });
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
