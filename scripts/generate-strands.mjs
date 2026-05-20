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
  const results = await Promise.all(
    keywords.map(kw =>
      fetch(`https://api.datamuse.com/words?rel_trg=${encodeURIComponent(kw)}&max=200`)
        .then(r => r.json())
        .catch(() => [])
    )
  );
  let words = results.flat()
    .filter(w => w.score > 500)
    .map(w => w.word.toLowerCase())
    .filter(w => /^[a-z]+$/.test(w) && w.length >= 4 && w.length <= 8);

  // If too few words, try ml= (means like) with lower threshold
  if (words.length < 20) {
    const fallback = await Promise.all(
      keywords.slice(0, 2).map(kw =>
        fetch(`https://api.datamuse.com/words?ml=${encodeURIComponent(kw)}&max=200`)
          .then(r => r.json())
          .catch(() => [])
      )
    );
    const extra = fallback.flat()
      .filter(w => w.score > 1000)
      .map(w => w.word.toLowerCase())
      .filter(w => /^[a-z]+$/.test(w) && w.length >= 4 && w.length <= 8);
    words = [...new Set([...words, ...extra])];
  }

  return [...new Set(words)];
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
  const byLength = { 4: [], 5: [], 6: [], 7: [], 8: [] };
  for (const w of themeWords) {
    if (byLength[w.length]) byLength[w.length].push(w);
  }

  if (byLength[8].length === 0) return null;

  for (const len of [4, 5, 6, 7, 8]) byLength[len] = shuffle(byLength[len], rng);

  const plans = shuffle([...PLANS], rng);

  for (const plan of plans) {
    const otherLengths = [...plan];
    const idx8 = otherLengths.indexOf(8);
    otherLengths.splice(idx8, 1);

    const needed = {};
    for (const l of otherLengths) needed[l] = (needed[l] || 0) + 1;
    let feasible = true;
    for (const [l, n] of Object.entries(needed)) {
      if ((byLength[l]?.length || 0) < n + 1) { feasible = false; break; }
    }
    if (!feasible) continue;

    for (let spanIdx = 0; spanIdx < Math.min(byLength[8].length, 5); spanIdx++) {
      const spangram = byLength[8][spanIdx];

      for (let combo = 0; combo < 20; combo++) {
        const otherWords = [];
        const used = new Set([spangram]);
        let ok = true;

        // Pick random words of each needed length
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
          const placed = backtrack(grid, allWords, 0, TOTAL, rng);
          if (placed) {
            // Strict validation: no word can be spelled via alternate cells
            const valid = placed.every(({ word, path }) => !canSpellWithOtherCells(grid, word, path));
            if (valid) {
              return { theme: themeName, spangram: spangram.toUpperCase(), grid, words: shuffle(placed, rng) };
            }
          }
        }
      }
    }
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
