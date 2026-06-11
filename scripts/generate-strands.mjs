#!/usr/bin/env node
/**
 * Generates Span.IT puzzles using the Datamuse API for themed word selection.
 * Usage: node scripts/generate-strands.mjs [days=60]
 *
 * Each puzzle:
 * - Has a theme (e.g. "Ocean Life")
 * - All words fetched from Datamuse API related to that theme
 * - Exactly 1 spangram: an 8-letter word that is the key word for the theme
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

async function fetchThemeWords(topics) {
  const keywords = topics.split(',').map(k => k.trim());

  // Primary: "means like" — strongest semantic connection
  // Request frequency metadata to filter out obscure words
  const mlResults = await Promise.all(
    keywords.map(kw =>
      fetch(`https://api.datamuse.com/words?ml=${encodeURIComponent(kw)}&max=200&md=f`)
        .then(r => r.json())
        .catch(() => [])
    )
  );

  // Score words by how many keywords they appear for (multi-hit = more relevant)
  const scoreMap = {};
  const freqMap = {};
  for (const results of mlResults) {
    for (const w of results) {
      const word = w.word.toLowerCase();
      if (!/^[a-z]+$/.test(word) || word.length < 4 || word.length > 8) continue;
      if (w.score < 5000) continue; // high threshold for tight relevance
      // Extract frequency from tags (format: "f:123.456")
      const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
      const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
      if (freq < 1.0) continue; // skip very rare/obscure words
      scoreMap[word] = (scoreMap[word] || 0) + w.score;
      freqMap[word] = Math.max(freqMap[word] || 0, freq);
    }
  }

  // Sort by combined score — highest relevance first
  let words = Object.entries(scoreMap)
    .sort((a, b) => b[1] - a[1])
    .map(([w]) => w);

  // If not enough, lower threshold but still require minimum frequency
  if (words.length < 25) {
    for (const results of mlResults) {
      for (const w of results) {
        const word = w.word.toLowerCase();
        if (!/^[a-z]+$/.test(word) || word.length < 4 || word.length > 8) continue;
        if (w.score < 2000) continue;
        const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
        const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
        if (freq < 0.5) continue; // slightly lower bar for fallback, but still filter obscure
        if (!words.includes(word)) words.push(word);
      }
    }
  }

  return words;
}

// Fetch words related to a specific spangram word (for tighter puzzle coherence)
async function fetchSpangramRelatedWords(spangram) {
  const results = await fetch(`https://api.datamuse.com/words?ml=${encodeURIComponent(spangram)}&max=200&md=f`)
    .then(r => r.json())
    .catch(() => []);

  const words = [];
  for (const w of results) {
    const word = w.word.toLowerCase();
    if (!/^[a-z]+$/.test(word) || word.length < 4 || word.length > 8) continue;
    if (word === spangram) continue;
    const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
    const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
    if (freq < 1.0) continue;
    words.push(word);
  }
  return words;
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

// Word-length plans summing to 48
const PLANS = [
  // 6 words
  [8, 8, 8, 8, 8, 8],
  [8, 8, 8, 8, 8, 8],
  // 7 words
  [8, 8, 8, 8, 6, 5, 5],
  [8, 8, 7, 7, 6, 6, 6],
  // 8 words
  [8, 8, 7, 6, 5, 5, 5, 4],
  [8, 8, 7, 6, 6, 5, 4, 4],
  [8, 8, 7, 7, 5, 5, 4, 4],
  [8, 8, 8, 6, 5, 5, 4, 4],
  [8, 7, 7, 7, 6, 5, 4, 4],
  [8, 7, 7, 6, 6, 6, 4, 4],
  // 9 words
  [8, 7, 6, 5, 5, 5, 4, 4, 4],
  [8, 6, 6, 6, 5, 5, 4, 4, 4],
  [8, 7, 7, 5, 5, 4, 4, 4, 4],
  [8, 6, 6, 5, 5, 5, 5, 4, 4],
];

// ─── Puzzle Generator ─────────────────────────────────────────────────────────

async function generatePuzzle(dateStr, themeWords, themeName, rng) {
  // Get 8-letter words from theme as spangram candidates
  const spangrams = themeWords.filter(w => w.length === 8);
  if (spangrams.length === 0) return null;

  const shuffledSpangrams = shuffle(spangrams, rng);
  const plans = shuffle([...PLANS], rng);

  for (let spanIdx = 0; spanIdx < Math.min(shuffledSpangrams.length, 5); spanIdx++) {
    const spangram = shuffledSpangrams[spanIdx];

    // Fetch words related to this specific spangram
    const relatedWords = await fetchSpangramRelatedWords(spangram);
    // Also include theme words as fallback
    const allCandidates = [...new Set([...relatedWords, ...themeWords])].filter(w => w !== spangram);

    const byLength = { 4: [], 5: [], 6: [], 7: [], 8: [] };
    for (const w of allCandidates) {
      if (byLength[w.length]) byLength[w.length].push(w);
    }
    for (const len of [4, 5, 6, 7, 8]) byLength[len] = shuffle(byLength[len], rng);

    for (const plan of plans) {
      const otherLengths = [...plan];
      const idx8 = otherLengths.indexOf(8);
      otherLengths.splice(idx8, 1);

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
          const pick = candidates[Math.floor(rng() * candidates.length)];
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
    // Small delay between spangram attempts to be polite to API
    await new Promise(r => setTimeout(r, 150));
  }
  return null;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

const days = parseInt(process.argv[2] ?? '60', 10);

// Use local date to avoid UTC offset issues
function localDateStr(d) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}
const today = new Date();

// Pre-fetch all theme word lists (cache them)
console.log('Fetching theme words from Datamuse API...');
const themeCache = {};
for (const theme of THEMES) {
  process.stdout.write(`  ${theme.name} ... `);
  try {
    themeCache[theme.name] = await fetchThemeWords(theme.topics);
    console.log(`${themeCache[theme.name].length} words`);
  } catch (e) {
    console.log(`FAILED: ${e.message}`);
    themeCache[theme.name] = [];
  }
  // Small delay to be polite to the API
  await new Promise(r => setTimeout(r, 200));
}

console.log('\nGenerating puzzles...');
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
  let usedTheme = null;

  for (const theme of themeOrder) {
    const words = themeCache[theme.name] || [];
    if (words.length < 10) continue;

    process.stdout.write(`${dateStr} [${theme.name}] ... `);
    puzzle = await generatePuzzle(dateStr, words, theme.name, rng);
    if (puzzle) {
      usedTheme = theme.name;
      break;
    }
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
