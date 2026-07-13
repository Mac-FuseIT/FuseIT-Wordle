#!/usr/bin/env node
/**
 * Generates Span.IT puzzles using the Datamuse API for themed word selection.
 * Usage: node scripts/generate-strands.mjs [days=60]
 *
 * Each puzzle:
 * - Has a theme (e.g. "Ocean Life")
 * - All words fetched from Datamuse API related to that theme
 * - Exactly 1 spangram: a 6-8 letter word tightly related to the theme
 */

import { execSync } from 'child_process';
import { writeFileSync, unlinkSync } from 'fs';
import { THEMES } from './themes.mjs';

// ─── Seeded RNG ───────────────────────────────────────────────────────────────

function hashStr(str) {
  let h = 0xdeadbeef;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 2654435761);
    h = (h << 13) | (h >>> 19);
  }
  return (h ^ (h >>> 16)) >>> 0;
}

function seededRng(seed) {
  let h = 0xdeadbeef ^ seed;
  return () => {
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    h = (h ^ (h >>> 16)) >>> 0;
    return h / 4294967296;
  };
}

function shuffle(arr, rng) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// ─── Datamuse API ─────────────────────────────────────────────────────────────

// The spangram should BE the topic word itself.
// If the topic doesn't fit 6-8 letters, try simple transformations.
// If nothing works, return empty (theme will be skipped).
async function fetchSpangramCandidates(topic) {
  const candidates = [];
  const lower = topic.toLowerCase();
  const singular = lower.replace(/s$/, '');

  // Strategy 1: Topic itself fits 6-8 letters
  if (/^[a-z]+$/.test(lower) && lower.length >= 6 && lower.length <= 8) {
    candidates.push(lower);
  }

  // Strategy 2: Singular form fits
  if (/^[a-z]+$/.test(singular) && singular.length >= 6 && singular.length <= 8 && singular !== lower) {
    candidates.push(singular);
  }

  // Strategy 3: Plural form fits (add 's' to topic)
  const plural = lower + 's';
  if (lower.length === 5 && /^[a-z]+$/.test(plural) && !candidates.length) {
    // Only use plurals that make linguistic sense
    // (not "chesss" or "icees" — only regular plurals of 5-letter nouns)
    candidates.push(plural);
  }

  // If we have candidates, return them — topic itself is always best
  if (candidates.length > 0) return candidates;

  // Strategy 4: For short/long topics, try very tight synonyms only
  // Use rel_syn (exact synonyms) — NOT rel_spc/rel_gen which can drift
  const synRes = await fetch(
    `https://api.datamuse.com/words?rel_syn=${encodeURIComponent(lower)}&max=10&md=f`
  ).then(r => r.json()).catch(() => []);

  for (const w of synRes) {
    const word = w.word.toLowerCase();
    if (!/^[a-z]+$/.test(word) || word.length < 6 || word.length > 8) continue;
    const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
    const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
    if (freq < 1.0) continue;
    candidates.push(word);
  }

  // Also try singular synonym
  if (singular !== lower) {
    const synRes2 = await fetch(
      `https://api.datamuse.com/words?rel_syn=${encodeURIComponent(singular)}&max=10&md=f`
    ).then(r => r.json()).catch(() => []);
    for (const w of synRes2) {
      const word = w.word.toLowerCase();
      if (!/^[a-z]+$/.test(word) || word.length < 6 || word.length > 8) continue;
      if (candidates.includes(word)) continue;
      const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
      const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
      if (freq < 1.0) continue;
      candidates.push(word);
    }
  }

  // If still nothing, return empty — this theme will be skipped
  // (better to skip than generate garbage like "ERUPTION" for "hives")
  return candidates;
}

// Fetch fill words tightly related to the topic (the spangram IS the topic)
async function fetchWordsForSpangram(spangram, topic) {
  const queryWord = topic;
  const singular = queryWord.replace(/s$/, '');
  // Also try the spangram itself as a query term (may differ from topic for short topics)
  const queries = [singular];
  if (queryWord !== singular) queries.push(queryWord);
  if (spangram !== singular && spangram !== queryWord) queries.push(spangram);

  // Fire tight queries for all query variants
  const allResults = { gen: [], com: [], trg: [], jjb: [] };

  for (const q of queries) {
    const [trgRes, genRes, comRes, jjbRes] = await Promise.all([
      fetch(`https://api.datamuse.com/words?rel_trg=${encodeURIComponent(q)}&topics=${encodeURIComponent(topic)}&max=100&md=f,p`).then(r => r.json()).catch(() => []),
      fetch(`https://api.datamuse.com/words?rel_gen=${encodeURIComponent(q)}&max=60&md=f,p`).then(r => r.json()).catch(() => []),
      fetch(`https://api.datamuse.com/words?rel_com=${encodeURIComponent(q)}&max=40&md=f,p`).then(r => r.json()).catch(() => []),
      fetch(`https://api.datamuse.com/words?rel_jjb=${encodeURIComponent(q)}&topics=${encodeURIComponent(topic)}&max=50&md=f,p`).then(r => r.json()).catch(() => []),
    ]);
    allResults.trg.push(...trgRes);
    allResults.gen.push(...genRes);
    allResults.com.push(...comRes);
    allResults.jjb.push(...jjbRes);
  }

  const scored = {};

  function isProperNoun(w) {
    // Check tags for 'prop' (proper noun)
    const tags = w.tags || [];
    if (tags.includes('prop')) return true;
    // If the word as returned starts with uppercase, likely proper noun
    if (w.word && w.word[0] === w.word[0].toUpperCase() && w.word[0] !== w.word[0].toLowerCase()) return true;
    return false;
  }

  function processResults(results, bonus) {
    for (const w of results) {
      if (isProperNoun(w)) continue; // Skip proper nouns
      const word = w.word.toLowerCase();
      if (!/^[a-z]+$/.test(word) || word.length < 4 || word.length > 8) continue;
      if (word === spangram || word === topic || word === singular) continue;
      const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
      const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
      if (freq < 2.0) continue;
      // Use FIXED bonus only — do NOT use w.score (it's word2vec distance, not relevance)
      scored[word] = (scored[word] || 0) + bonus;
    }
  }

  // Higher bonus = more likely to be picked. Tight relations outrank loose ones.
  processResults(allResults.gen, 100000);  // hyponyms (types of)
  processResults(allResults.com, 90000);   // parts/comprises
  processResults(allResults.trg, 80000);   // co-occurrence
  processResults(allResults.jjb, 70000);   // adjectives

  // ml as amplifier only: boost words already scored from tight sources
  const mlRes = await fetch(
    `https://api.datamuse.com/words?ml=${encodeURIComponent(queryWord)}&topics=${encodeURIComponent(queryWord)}&max=150&md=f,p`
  ).then(r => r.json()).catch(() => []);

  for (const w of mlRes) {
    if (isProperNoun(w)) continue;
    const word = w.word.toLowerCase();
    if (!/^[a-z]+$/.test(word) || word.length < 4 || word.length > 8) continue;
    if (word === spangram || word === topic || word === singular) continue;
    const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
    const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
    if (freq < 2.0) continue;
    if (scored[word]) {
      scored[word] += 10000; // amplify existing good words
    }
  }

  // Fallback: if tight sources produced fewer than 15 words, allow ml (strict freq)
  if (Object.keys(scored).length < 15) {
    for (const w of mlRes) {
      if (isProperNoun(w)) continue;
      const word = w.word.toLowerCase();
      if (!/^[a-z]+$/.test(word) || word.length < 4 || word.length > 8) continue;
      if (word === spangram || word === topic || word === singular) continue;
      if (scored[word]) continue; // already scored
      const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
      const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
      if (freq < 3.0) continue; // stricter freq for fallback
      scored[word] = 1000; // very low score — only used if nothing better exists
    }
  }

  // Words that appear in multiple signal sources get a bonus multiplier
  const signalCounts = {};
  function countSignal(results) {
    for (const w of results) {
      const word = w.word.toLowerCase();
      if (scored[word]) signalCounts[word] = (signalCounts[word] || 0) + 1;
    }
  }
  countSignal(allResults.gen);
  countSignal(allResults.com);
  countSignal(allResults.trg);
  countSignal(allResults.jjb);

  // Words in 2+ sources are more reliable — boost them
  for (const [word, count] of Object.entries(signalCounts)) {
    if (count >= 2 && scored[word]) scored[word] = Math.floor(scored[word] * 1.5);
    if (count >= 3 && scored[word]) scored[word] = Math.floor(scored[word] * 2);
  }

  return Object.entries(scored)
    .sort((a, b) => b[1] - a[1])
    .map(([w]) => w);
}

// ─── Grid Placement ───────────────────────────────────────────────────────────

const ROWS = 8, COLS = 6, TOTAL = 48;
const DIRS = [[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]];

function findPath(grid, letters, idx, r, c, visited, rng) {
  if (r < 0 || r >= ROWS || c < 0 || c >= COLS) return null;
  const key = r * COLS + c;
  if (visited & (1n << BigInt(key))) return null;
  if (grid[r][c] !== null) return null;
  if (idx === letters.length - 1) return [[r, c]];
  const newVisited = visited | (1n << BigInt(key));
  for (const [dr, dc] of shuffle([...DIRS], rng)) {
    const rest = findPath(grid, letters, idx + 1, r + dr, c + dc, newVisited, rng);
    if (rest) return [[r, c], ...rest];
  }
  return null;
}

function placeOnGrid(grid, word, path) {
  word.toUpperCase().split('').forEach((l, i) => { grid[path[i][0]][path[i][1]] = l; });
}

function removeFromGrid(grid, path) {
  path.forEach(([r, c]) => { grid[r][c] = null; });
}

function emptyCells(grid) {
  const cells = [];
  for (let r = 0; r < ROWS; r++)
    for (let c = 0; c < COLS; c++)
      if (grid[r][c] === null) cells.push([r, c]);
  return cells;
}

let backtrackIter = 0;
const BACKTRACK_LIMIT = 50000;

function backtrack(grid, words, idx, remaining, rng) {
  if (++backtrackIter > BACKTRACK_LIMIT) return null;
  if (idx === words.length) return remaining === 0 ? [] : null;
  const word = words[idx];
  const letters = word.toUpperCase().split('');
  for (const [sr, sc] of shuffle(emptyCells(grid), rng)) {
    const path = findPath(grid, letters, 0, sr, sc, 0n, rng);
    if (!path) continue;
    placeOnGrid(grid, word, path);
    const rest = backtrack(grid, words, idx + 1, remaining - word.length, rng);
    if (rest !== null) return [{ word: word.toUpperCase(), path }, ...rest];
    removeFromGrid(grid, path);
    if (backtrackIter > BACKTRACK_LIMIT) return null;
  }
  return null;
}

// Check if a word can be spelled via ANY path other than its canonical one
function canSpellWithOtherCells(grid, word, ownPath) {
  const ownSet = new Set(ownPath.map(([r, c]) => r * COLS + c));
  const letters = word.toUpperCase().split('');
  let altFound = false;

  function dfs(idx, r, c, visited, usedOwn) {
    if (altFound) return;
    if (r < 0 || r >= ROWS || c < 0 || c >= COLS) return;
    const key = r * COLS + c;
    if (visited.has(key)) return;
    if (grid[r][c] !== letters[idx]) return;
    const isOwnCell = ownSet.has(key);
    const newUsedOwn = usedOwn + (isOwnCell ? 0 : 1); // count cells NOT in own path
    if (idx === letters.length - 1) {
      // If at least one cell differs from the canonical path, it's an alternate
      if (newUsedOwn > 0) altFound = true;
      return;
    }
    visited.add(key);
    for (const [dr, dc] of DIRS) {
      dfs(idx + 1, r + dr, c + dc, visited, newUsedOwn);
      if (altFound) break;
    }
    visited.delete(key);
  }

  for (let r = 0; r < ROWS && !altFound; r++)
    for (let c = 0; c < COLS && !altFound; c++)
      if (grid[r][c] === letters[0]) dfs(0, r, c, new Set(), 0);

  return altFound;
}

// Word-length plans for remaining words (excluding spangram) summing to (48 - spangramLength)
// Keyed by spangram length
const PLANS_BY_SPANGRAM = {
  8: [
    // Remaining = 40
    [8, 8, 8, 8, 8],
    [8, 8, 8, 6, 5, 5],
    [8, 7, 7, 6, 6, 6],
    [8, 7, 6, 5, 5, 5, 4],
    [8, 7, 6, 6, 5, 4, 4],
    [8, 7, 7, 5, 5, 4, 4],
    [8, 8, 6, 5, 5, 4, 4],
    [7, 7, 7, 6, 5, 4, 4],
    [7, 7, 6, 6, 6, 4, 4],
    [7, 6, 5, 5, 5, 4, 4, 4],
    [6, 6, 6, 5, 5, 4, 4, 4],
    [7, 7, 5, 5, 4, 4, 4, 4],
    [6, 6, 5, 5, 5, 5, 4, 4],
  ],
  7: [
    // Remaining = 41
    [8, 8, 8, 8, 5, 4],
    [8, 8, 7, 6, 6, 6],
    [8, 8, 7, 7, 6, 5],
    [8, 7, 7, 6, 5, 4, 4],
    [8, 8, 6, 6, 5, 4, 4],
    [8, 7, 7, 5, 5, 5, 4],
    [8, 7, 6, 6, 6, 4, 4],
    [7, 7, 6, 6, 5, 5, 5],
    [8, 7, 6, 5, 5, 5, 5],
    [7, 6, 6, 6, 5, 5, 6],
    [8, 6, 6, 5, 5, 5, 6],
    [7, 7, 6, 5, 4, 4, 4, 4],
    [8, 6, 6, 5, 4, 4, 4, 4],
  ],
  6: [
    // Remaining = 42
    [8, 8, 8, 6, 6, 6],
    [8, 8, 7, 7, 6, 6],
    [8, 8, 8, 7, 7, 4],
    [8, 8, 7, 6, 5, 4, 4],
    [8, 7, 7, 7, 5, 4, 4],
    [8, 8, 6, 6, 6, 4, 4],
    [8, 7, 7, 6, 6, 4, 4],
    [8, 7, 6, 6, 5, 5, 5],
    [7, 7, 7, 7, 6, 4, 4],
    [8, 7, 6, 5, 5, 5, 6],
    [7, 7, 6, 6, 5, 5, 6],
    [8, 6, 6, 6, 4, 4, 4, 4],
    [7, 7, 6, 5, 5, 4, 4, 4],
  ],
};

// ─── Puzzle Generator ─────────────────────────────────────────────────────────

async function generatePuzzle(dateStr, themeName, themeTopics, rng) {
  const topic = themeTopics.split(',')[0].trim();

  // Step 1: Get spangram candidates from theme topic
  const spangramCandidates = await fetchSpangramCandidates(topic);
  if (spangramCandidates.length === 0) return null;

  // Step 2: For each spangram, fetch fill words based on THAT spangram
  for (let spanIdx = 0; spanIdx < Math.min(spangramCandidates.length, 5); spanIdx++) {
    const spangram = spangramCandidates[spanIdx];

    // Fetch words related to the spangram — this ensures coherence
    const fillWords = await fetchWordsForSpangram(spangram, topic);
    if (fillWords.length < 10) continue;

    const plans = shuffle([...(PLANS_BY_SPANGRAM[spangram.length] || PLANS_BY_SPANGRAM[8])], rng);

    const byLength = { 4: [], 5: [], 6: [], 7: [], 8: [] };
    for (const w of fillWords) {
      if (byLength[w.length] && w !== spangram) byLength[w.length].push(w);
    }

    for (const plan of plans) {
      const otherLengths = [...plan];
      const needed = {};
      for (const l of otherLengths) needed[l] = (needed[l] || 0) + 1;
      let feasible = true;
      for (const [l, n] of Object.entries(needed)) {
        if ((byLength[l]?.length || 0) < n) { feasible = false; break; }
      }
      if (!feasible) continue;

      for (let combo = 0; combo < 20; combo++) {
        const otherWords = [];
        const used = new Set([spangram]);
        let ok = true;

        for (const len of otherLengths) {
          const candidates = byLength[len].filter(w => !used.has(w));
          if (candidates.length === 0) { ok = false; break; }
          // Pick from top of list (highest relevance to spangram)
          const pick = candidates[Math.floor(rng() * Math.min(candidates.length, 3))];
          otherWords.push(pick);
          used.add(pick);
        }
        if (!ok) continue;

        const allWords = [spangram, ...otherWords];

        for (let attempt = 0; attempt < 5; attempt++) {
          const grid = Array.from({ length: ROWS }, () => Array(COLS).fill(null));
          backtrackIter = 0;
          const placed = backtrack(grid, allWords, 0, TOTAL, rng);
          if (placed) {
            const valid = placed.every(({ word, path }) => !canSpellWithOtherCells(grid, word, path));
            if (valid) {
              return { theme: themeName, spangram: spangram.toUpperCase(), grid, words: shuffle(placed, rng) };
            }
          }
        }
      }
    }
    await new Promise(r => setTimeout(r, 250));
  }
  return null;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

const days = parseInt(process.argv[2] ?? '60', 10);

function localDateStr(d) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}
const today = new Date();

console.log('Generating puzzles...');
const sqlLines = [];
let ok = 0, fail = 0;

for (let i = 0; i < days; i++) {
  const d = new Date(today);
  d.setDate(d.getDate() + i);
  // Skip weekends
  if (d.getDay() === 0 || d.getDay() === 6) continue;
  const dateStr = localDateStr(d);

  const rng = seededRng(hashStr('spanit:' + dateStr));
  const themeOrder = shuffle([...THEMES], rng);

  let puzzle = null;

  for (const theme of themeOrder) {
    process.stdout.write(`${dateStr} [${theme.name}] ... `);
    puzzle = await generatePuzzle(dateStr, theme.name, theme.topics, rng);
    if (puzzle) break;
    console.log('no valid grid, trying next theme...');
  }

  if (!puzzle) {
    console.log(`${dateStr} FAILED (no theme produced a valid grid)`);
    fail++;
    continue;
  }

  const grid = JSON.stringify(puzzle.grid).replace(/'/g, "''");
  const themeWords = JSON.stringify(puzzle.words).replace(/'/g, "''");
  const themeName = puzzle.theme.replace(/'/g, "''");
  const spangram = puzzle.spangram.replace(/'/g, "''");

  sqlLines.push(`INSERT OR IGNORE INTO spanit_puzzles (date, grid, theme, spangram, theme_words) VALUES ('${dateStr}', '${grid}', '${themeName}', '${spangram}', '${themeWords}');`);
  console.log(`OK (${puzzle.words.length} words, spangram: ${puzzle.spangram})`);
  ok++;
}

const sqlFile = '/tmp/spanit-insert.sql';
writeFileSync(sqlFile, sqlLines.join('\n') + '\n');
console.log(`\nGenerated: ${ok}, Failed: ${fail}`);
console.log('Pushing to D1...');

try {
  execSync(`npx wrangler d1 execute fuseit-wordle-db --file=${sqlFile} --remote`, { stdio: 'inherit' });
  console.log('Done!');
} catch (e) {
  console.error('Push failed. SQL saved at', sqlFile);
} finally {
  try { unlinkSync(sqlFile); } catch (_) {}
}
