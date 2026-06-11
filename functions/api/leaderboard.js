import { getToday, jsonResponse, errorResponse, requireAuth, isValidDate } from '../../src/db.js';
import { getOrCreateDailyWord } from '../../src/word-selection.js';

function getPrevMonth(month) {
  const [y, m] = month.split('-').map(Number);
  const d = new Date(y, m - 2, 1);
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0');
}

function lastDayOfMonth(month) {
  const [y, m] = month.split('-').map(Number);
  return month + '-' + String(new Date(y, m, 0).getDate()).padStart(2, '0');
}

async function getMonthlyLeaderboard(env, monthStart, monthEnd) {
  return env.DB.prepare(`
    WITH month_days AS (
      SELECT date, length FROM daily_words WHERE date >= ? AND date <= ?
    ),
    user_scores AS (
      SELECT u.id, u.name, u.email,
        SUM(COALESCE(a.num_guesses, md.length + 4)) AS totalGuesses,
        COUNT(a.id) AS daysPlayed
      FROM users u
      CROSS JOIN month_days md
      LEFT JOIN attempts a ON a.user_id = u.id AND a.date = md.date
      WHERE EXISTS (SELECT 1 FROM attempts WHERE user_id = u.id AND date >= ? AND date <= ?)
      GROUP BY u.id
    )
    SELECT name, email, totalGuesses, daysPlayed FROM user_scores ORDER BY totalGuesses ASC
  `).bind(monthStart, monthEnd, monthStart, monthEnd).all();
}

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const rawDate = url.searchParams.get('date');
  const date = (rawDate && isValidDate(rawDate)) ? rawDate : getToday();

  // Daily leaderboard
  const daily = await env.DB.prepare(
    'SELECT u.name, a.num_guesses AS numGuesses, a.solved FROM attempts a JOIN users u ON u.id = a.user_id WHERE a.date = ? ORDER BY a.solved DESC, a.num_guesses ASC'
  ).bind(date).all();

  // Current month leaderboard
  const month = date.substring(0, 7);
  const today = getToday();
  const monthStart = month + '-01';
  const monthEnd = today.startsWith(month) ? today : lastDayOfMonth(month);
  await getOrCreateDailyWord(env.DB, date);

  const monthly = await getMonthlyLeaderboard(env, monthStart, monthEnd);

  // Day breakdown for requesting user — only days that exist in daily_words
  const auth = await requireAuth(request, env);
  const userId = auth ? auth.userId : null;
  let dayBreakdown = [];
  let currentUserName = null;
  if (userId) {
    const user = await env.DB.prepare('SELECT nickname, name FROM users WHERE id = ?').bind(userId).first();
    if (user) currentUserName = user.nickname || user.name;
    const breakdown = await env.DB.prepare(`
      SELECT dw.date, dw.word, dw.length,
        a.num_guesses AS numGuesses, a.solved
      FROM daily_words dw
      LEFT JOIN attempts a ON a.date = dw.date AND a.user_id = ?
      WHERE dw.date >= ? AND dw.date <= ?
      ORDER BY dw.date DESC
    `).bind(userId, monthStart, monthEnd).all();
    dayBreakdown = (breakdown.results || []).reverse().map(r => {
      const isToday = r.date === today;
      const played = r.numGuesses !== null;
      return {
        date: r.date,
        word: (isToday && !played) ? '?' .repeat(r.length) : r.word,
        length: r.length,
        numGuesses: r.numGuesses ?? r.length + 4,
        played,
        solved: r.solved === 1,
      };
    });
  }

  // Previous month top 3 (only show if current day is 1-7)
  const currentDay = parseInt(today.split('-')[2], 10);
  let prevTop3 = [];
  let prevMonth = '';
  if (currentDay <= 7) {
    prevMonth = getPrevMonth(month);
    const prevStart = prevMonth + '-01';
    const prevEnd = lastDayOfMonth(prevMonth);
    const prevMonthly = await getMonthlyLeaderboard(env, prevStart, prevEnd);
    prevTop3 = (prevMonthly.results || []).slice(0, 3);
  }

  return jsonResponse({
    daily: daily.results || [],
    monthly: monthly.results || [],
    dayBreakdown,
    previousMonth: prevTop3,
    previousMonthLabel: prevMonth,
    currentUserName,
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
