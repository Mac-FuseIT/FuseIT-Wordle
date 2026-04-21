import { getToday, jsonResponse, errorResponse } from '../../src/db.js';
import { getOrCreateDailyWord } from '../../src/word-selection.js';

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const date = url.searchParams.get('date') || getToday();

  // Daily leaderboard
  const daily = await env.DB.prepare(
    'SELECT u.name, a.num_guesses AS numGuesses, a.solved FROM attempts a JOIN users u ON u.id = a.user_id WHERE a.date = ? ORDER BY a.solved DESC, a.num_guesses ASC'
  ).bind(date).all();

  // Monthly leaderboard — sum of attempts for the month
  const month = date.substring(0, 7); // YYYY-MM
  const { length } = await getOrCreateDailyWord(env.DB, date);

  // Get all days in the month up to today
  const today = getToday();
  const monthStart = month + '-01';
  const monthEnd = today >= monthStart ? (today.startsWith(month) ? today : month + '-31') : month + '-01';

  const monthly = await env.DB.prepare(`
    WITH month_days AS (
      SELECT date, length FROM daily_words WHERE date >= ? AND date <= ?
    ),
    user_scores AS (
      SELECT u.id, u.name,
        SUM(COALESCE(a.num_guesses, md.length + 1)) AS totalGuesses,
        COUNT(a.id) AS daysPlayed
      FROM users u
      CROSS JOIN month_days md
      LEFT JOIN attempts a ON a.user_id = u.id AND a.date = md.date
      WHERE EXISTS (SELECT 1 FROM attempts WHERE user_id = u.id AND date >= ? AND date <= ?)
      GROUP BY u.id
    )
    SELECT name, totalGuesses, daysPlayed FROM user_scores ORDER BY totalGuesses ASC
  `).bind(monthStart, monthEnd, monthStart, monthEnd).all();

  return jsonResponse({
    daily: daily.results || [],
    monthly: monthly.results || [],
  });
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    },
  });
}
