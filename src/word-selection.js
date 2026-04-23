import { wordsByLength } from './words.js';

// MurmurHash3-inspired mixer — much better distribution than djb2
function hash(str) {
  let h = 0xdeadbeef;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 2654435761);
    h = (h << 13) | (h >>> 19);
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507);
  h = Math.imul(h ^ (h >>> 13), 3266489909);
  return (h ^ (h >>> 16)) >>> 0;
}

export function getTodayWord(dateStr) {
  const lengthHash = hash('length:' + dateStr);
  const wordLength = 4 + (lengthHash % 5);
  const words = wordsByLength[wordLength];
  const wordHash = hash('word:' + dateStr);
  const wordIndex = wordHash % words.length;
  return { word: words[wordIndex], length: wordLength };
}

export async function getOrCreateDailyWord(db, dateStr) {
  const row = await db.prepare('SELECT word, length FROM daily_words WHERE date = ?').bind(dateStr).first();
  if (row) return row;
  const { word, length } = getTodayWord(dateStr);
  await db.prepare('INSERT OR IGNORE INTO daily_words (date, word, length) VALUES (?, ?, ?)').bind(dateStr, word, length).run();
  return { word, length };
}
