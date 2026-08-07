import { wordsByLength } from './words.js';

// MurmurHash3-inspired mixer — same as word-selection.js for consistency
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

export function getChainItPuzzle(dateStr) {
  // Pick length: 4, 5, or 6
  const lengthHash = hash('chainit-length:' + dateStr);
  const wordLength = 4 + (lengthHash % 3); // 4, 5, or 6

  // Filter to only real English words — eliminates tech acronyms (GRPC, CSRF,
  // SMTP, NUXTJS etc.) that have no valid 1-letter neighbours in a word ladder.
  // Rules:
  //   • At least 1 vowel for any word (drops grpc, csrf, smtp, nmap, ctrl …)
  //   • At least 2 vowels for 5+ letter words (drops single-vowel tech jargon)
  //   • No 4+ consecutive consonants (drops nuxtjs, nxtjs …)
  //   • No 3+ consecutive consonants for 4-letter words (drops json, ctrl …)
  const allWords = wordsByLength[wordLength];
  const words = (allWords || []).filter(w => {
    const vowelCount = (w.match(/[aeiou]/gi) || []).length;
    if (vowelCount < 1) return false;
    if (wordLength >= 5 && vowelCount < 2) return false;
    if (/[^aeiou]{4}/i.test(w)) return false;
    if (/[^aeiou]{3}/i.test(w) && wordLength <= 4) return false;
    return true;
  });
  if (!words || words.length < 2) return null;

  // Pick target word
  const targetHash = hash('chainit-target:' + dateStr);
  const targetIndex = targetHash % words.length;
  const targetWord = words[targetIndex];

  // Pick start word (different from target)
  const startHash = hash('chainit-start:' + dateStr);
  let startIndex = startHash % words.length;
  if (startIndex === targetIndex) {
    startIndex = (startIndex + 1) % words.length;
  }
  const startWord = words[startIndex];

  return { startWord, targetWord, length: wordLength };
}

export async function getOrCreateChainItPuzzle(db, dateStr) {
  // Check if puzzle already cached in DB
  const row = await db.prepare(
    'SELECT start_word, target_word, length FROM chainit_puzzles WHERE date = ?'
  ).bind(dateStr).first();

  if (row) return row;

  // Generate and cache
  const puzzle = getChainItPuzzle(dateStr);
  if (!puzzle) return null;

  await db.prepare(
    'INSERT OR IGNORE INTO chainit_puzzles (date, start_word, target_word, length) VALUES (?, ?, ?, ?)'
  ).bind(dateStr, puzzle.startWord, puzzle.targetWord, puzzle.length).run();

  return { start_word: puzzle.startWord, target_word: puzzle.targetWord, length: puzzle.length };
}
