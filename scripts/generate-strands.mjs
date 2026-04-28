/**
 * Pre-generates Span.IT puzzles and inserts them into D1.
 * Run with: node scripts/generate-strands.mjs [days=30]
 * Then push to remote: npx wrangler d1 execute fuseit-wordle-db --file=scripts/strands-insert.sql --remote
 */

import { generateStrandPuzzle } from '../src/strand-selection.js';
import { writeFileSync } from 'fs';

const days = parseInt(process.argv[2] ?? '30', 10);
const lines = [];

const today = new Date();
today.setHours(0, 0, 0, 0);

let generated = 0, skipped = 0;

for (let i = 0; i < days; i++) {
  const d = new Date(today);
  d.setDate(d.getDate() + i);
  const dateStr = d.toISOString().slice(0, 10);

  process.stdout.write(`Generating ${dateStr}... `);
  const puzzle = generateStrandPuzzle(dateStr);

  if (!puzzle.words.length) {
    console.log('FAILED (no words placed) — skipped');
    skipped++;
    continue;
  }

  const grid = JSON.stringify(puzzle.grid).replace(/'/g, "''");
  const words = JSON.stringify(puzzle.words).replace(/'/g, "''");
  lines.push(`INSERT OR IGNORE INTO strand_puzzles (date, grid, theme, spangram, theme_words) VALUES ('${dateStr}', '${grid}', '', '{}', '${words}');`);
  console.log(`OK (${puzzle.words.length} words)`);
  generated++;
}

const outFile = 'scripts/strands-insert.sql';
writeFileSync(outFile, lines.join('\n') + '\n');
console.log(`\nDone: ${generated} generated, ${skipped} skipped → ${outFile}`);
console.log(`Push to DB: npx wrangler d1 execute fuseit-wordle-db --file=${outFile} --remote`);
