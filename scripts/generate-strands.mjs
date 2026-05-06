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
  const keyword = topics.split(',')[0].trim();
  // rel_trg = "triggered by" - words strongly associated with the topic
  // Use multiple keywords and combine results
  const keywords = topics.split(',').map(k => k.trim()).slice(0, 3);
  const results = await Promise.all(
    keywords.map(kw =>
      fetch(`https://api.datamuse.com/words?rel_trg=${encodeURIComponent(kw)}&max=200`)
        .then(r => r.json())
        .catch(() => [])
    )
  );
  // Only keep high-scoring words (score > 500 = strongly associated)
  const all = results.flat()
    .filter(w => w.score > 500)
    .map(w => w.word.toLowerCase());
  return [...new Set(all)].filter(w => /^[a-z]+$/.test(w) && w.length >= 4 && w.length <= 8);
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

function backtrack(grid, words, idx, remaining, rng) {
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
  }
  return null;
}

// Check if a word can be spelled using cells NOT belonging to its own path
// (would make the puzzle ambiguous/unsolvable)
function canSpellWithOtherCells(grid, word, ownPath) {
  const ownCells = new Set(ownPath.map(([r, c]) => `${r}:${c}`));
  const letters = word.toUpperCase().split('');

  function dfs(idx, r, c, visited) {
    if (r < 0 || r >= ROWS || c < 0 || c >= COLS) return false;
    const key = `${r}:${c}`;
    if (ownCells.has(key) || visited.has(key)) return false;
    if (grid[r][c] !== letters[idx]) return false;
    if (idx === letters.length - 1) return true;
    visited.add(key);
    for (const [dr, dc] of DIRS) {
      if (dfs(idx + 1, r + dr, c + dc, visited)) { visited.delete(key); return true; }
    }
    visited.delete(key);
    return false;
  }

  for (let r = 0; r < ROWS; r++)
    for (let c = 0; c < COLS; c++)
      if (dfs(0, r, c, new Set())) return true;
  return false;
}

// Word-length plans summing to 48
const PLANS = [
  [8, 8, 7, 6, 5, 5, 5, 4],
  [8, 8, 7, 6, 6, 5, 4, 4],
  [8, 8, 7, 7, 5, 5, 4, 4],
  [8, 8, 8, 6, 5, 5, 4, 4],
  [8, 7, 7, 7, 6, 5, 4, 4],
  [8, 7, 7, 6, 6, 6, 4, 4],
  [8, 8, 8, 8, 6, 5, 5],
  [8, 8, 7, 7, 6, 6, 6],
];

// ─── Puzzle Generator ─────────────────────────────────────────────────────────

async function generatePuzzle(dateStr, themeWords, themeName, rng) {
  // Separate by length
  const byLength = { 4: [], 5: [], 6: [], 7: [], 8: [] };
  for (const w of themeWords) {
    if (byLength[w.length]) byLength[w.length].push(w);
  }

  // Need at least one 8-letter word for spangram
  if (byLength[8].length === 0) {
    console.log(`  No 8-letter words for theme "${themeName}", skipping`);
    return null;
  }

  // Shuffle all pools
  for (const len of [4, 5, 6, 7, 8]) byLength[len] = shuffle(byLength[len], rng);

  const spangram = byLength[8][0];

  // Try multiple plans
  const plans = shuffle([...PLANS], rng);
  for (const plan of plans) {
    // plan has one 8 (spangram) + others
    const otherLengths = [...plan];
    const idx8 = otherLengths.indexOf(8);
    otherLengths.splice(idx8, 1);

    // Check we have enough words of each length
    const needed = {};
    for (const l of otherLengths) needed[l] = (needed[l] || 0) + 1;
    let feasible = true;
    for (const [l, n] of Object.entries(needed)) {
      if ((byLength[l]?.length || 0) < n + 1) { feasible = false; break; } // +1 to skip spangram if it's also len 8
    }
    if (!feasible) continue;

    // Pick words
    const usedIdx = { 4: 0, 5: 0, 6: 0, 7: 0, 8: 1 }; // start 8 at 1 to skip spangram
    const otherWords = [];
    let ok = true;
    for (const len of otherLengths) {
      const pool = byLength[len];
      if (usedIdx[len] >= pool.length) { ok = false; break; }
      otherWords.push(pool[usedIdx[len]++]);
    }
    if (!ok) continue;

    const allWords = [spangram, ...otherWords];
    if (new Set(allWords).size !== allWords.length) continue;

    // Try to place on grid
    for (let attempt = 0; attempt < 3; attempt++) {
      const grid = Array.from({ length: ROWS }, () => Array(COLS).fill(null));
      const placed = backtrack(grid, allWords, 0, TOTAL, rng);
      if (placed && placed.every(({ word, path }) => !canSpellWithOtherCells(grid, word, path))) {
        return { theme: themeName, spangram: spangram.toUpperCase(), grid, words: placed };
      }
    }
  }
  return null;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

const days = parseInt(process.argv[2] ?? '60', 10);
const today = new Date();
today.setHours(0, 0, 0, 0);

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
  const dateStr = d.toISOString().slice(0, 10);

  const rng = seededRng(hashStr('spanit:' + dateStr));
  const theme = THEMES[Math.floor(rng() * THEMES.length)];
  const words = themeCache[theme.name] || [];

  process.stdout.write(`${dateStr} [${theme.name}] ... `);

  if (words.length < 10) {
    console.log('SKIPPED (not enough words)');
    fail++;
    continue;
  }

  const puzzle = await generatePuzzle(dateStr, words, theme.name, rng);
  if (!puzzle) {
    console.log('FAILED (could not place words)');
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
