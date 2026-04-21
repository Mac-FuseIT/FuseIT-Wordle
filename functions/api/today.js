import { getToday, jsonResponse } from '../../src/db.js';
import { getOrCreateDailyWord } from '../../src/word-selection.js';

export async function onRequestGet({ env }) {
  const date = getToday();
  const { length } = await getOrCreateDailyWord(env.DB, date);
  return jsonResponse({ date, wordLength: length, maxAttempts: length + 1 });
}
