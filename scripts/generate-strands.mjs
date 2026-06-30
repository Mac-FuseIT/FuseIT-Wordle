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

// Fetch spangram candidates (6-8 letters) related to the theme topic
async function fetchSpangramCandidates(topic) {
  const [mlRes, trgRes] = await Promise.all([
    fetch(`https://api.datamuse.com/words?ml=${encodeURIComponent(topic)}&max=150&md=f`).then(r => r.json()).catch(() => []),
    fetch(`https://api.datamuse.com/words?rel_trg=${encodeURIComponent(topic)}&max=80&md=f`).then(r => r.json()).catch(() => []),
  ]);

  const scored = {};
  for (const w of mlRes) {
    const word = w.word.toLowerCase();
    if (!/^[a-z]+$/.test(word) || word.length < 6 || word.length > 8) continue;
    if (word === topic) continue;
    const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
    const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
    if (freq < 2.0) continue;
    scored[word] = (scored[word] || 0) + (w.score || 0);
  }
  for (const w of trgRes) {
    const word = w.word.toLowerCase();
    if (!/^[a-z]+$/.test(word) || word.length < 6 || word.length > 8) continue;
    if (word === topic) continue;
    const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
    const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
    if (freq < 2.0) continue;
    scored[word] = (scored[word] || 0) + 50000; // boost rel_trg words
  }

  return Object.entries(scored)
    .sort((a, b) => b[1] - a[1])
    .map(([w]) => w);
}

// Fetch fill words (4-8 letters) related to the SPANGRAM word
async function fetchWordsForSpangram(spangram) {
  const [mlRes, trgRes] = await Promise.all([
    fetch(`https://api.datamuse.com/words?ml=${encodeURIComponent(spangram)}&max=200&md=f`).then(r => r.json()).catch(() => []),
    fetch(`https://api.datamuse.com/words?rel_trg=${encodeURIComponent(spangram)}&max=100&md=f`).then(r => r.json()).catch(() => []),
  ]);

  const scored = {};
  for (const w of mlRes) {
    const word = w.word.toLowerCase();
    if (!/^[a-z]+$/.test(word) || word.length < 4 || word.length > 8) continue;
    if (word === spangram) continue;
    const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
    const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
    if (freq < 3.0) continue; // only common, recognizable words
    scored[word] = (scored[word] || 0) + (w.score || 0);
  }
  for (const w of trgRes) {
    const word = w.word.toLowerCase();
    if (!/^[a-z]+$/.test(word) || word.length < 4 || word.length > 8) continue;
    if (word === spangram) continue;
    const freqTag = (w.tags || []).find(t => t.startsWith('f:'));
    const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
    if (freq < 3.0) continue;
    scored[word] = (scored[word] || 0) + 50000; // boost rel_trg
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
    const fillWords = await fetchWordsForSpangram(spangram);
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
    await new Promise(r => setTimeout(r, 150));
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
