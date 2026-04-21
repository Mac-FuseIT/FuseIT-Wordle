import { wordsByLength } from './words.js';

function hashDate(dateStr) {
  let hash = 0;
  for (let i = 0; i < dateStr.length; i++) {
    hash = ((hash << 5) - hash + dateStr.charCodeAt(i)) | 0;
  }
  return Math.abs(hash);
}

export function getTodayWord(dateStr) {
  const hash = hashDate(dateStr);
  const wordLength = 4 + (hash % 5); // random 4-8
  const words = wordsByLength[wordLength];
  const wordIndex = hashDate(dateStr + 'salt') % words.length;
  return { word: words[wordIndex], length: wordLength };
}

export async function getOrCreateDailyWord(db, dateStr) {
  const row = await db.prepare('SELECT word, length FROM daily_words WHERE date = ?').bind(dateStr).first();
  if (row) return row;
  const { word, length } = getTodayWord(dateStr);
  await db.prepare('INSERT OR IGNORE INTO daily_words (date, word, length) VALUES (?, ?, ?)').bind(dateStr, word, length).run();
  return { word, length };
}
