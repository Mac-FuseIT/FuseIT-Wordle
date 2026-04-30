#!/usr/bin/env node
/**
 * Pre-generates Span.IT puzzles and pushes them directly to D1.
 * Usage: node scripts/generate-strands.mjs [days=60]
 * TO RUN:
 * node scripts/generate-strands.mjs 60 
 */

import { generateStrandPuzzle } from '../src/strand-selection.js';
import { execSync } from 'child_process';
import { writeFileSync, unlinkSync } from 'fs';

const days = parseInt(process.argv[2] ?? '60', 10);
const today = new Date();
today.setHours(0, 0, 0, 0);

const sqlLines = [];
let ok = 0, fail = 0;

for (let i = 0; i < days; i++) {
  const d = new Date(today);
  d.setDate(d.getDate() + i);
  const dateStr = d.toISOString().slice(0, 10);

  process.stdout.write(`${dateStr} ... `);
  const puzzle = generateStrandPuzzle(dateStr);

  if (!puzzle.words.length) {
    console.log('FAILED');
    fail++;
    continue;
  }

  const grid = JSON.stringify(puzzle.grid).replace(/'/g, "''");
  const words = JSON.stringify(puzzle.words).replace(/'/g, "''");
  sqlLines.push(`INSERT OR IGNORE INTO strand_puzzles (date, grid, theme, spangram, theme_words) VALUES ('${dateStr}', '${grid}', '', '{}', '${words}');`);
  console.log(`OK (${puzzle.words.length} words)`);
  ok++;
}

const sqlFile = '/tmp/strands-insert.sql';
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
