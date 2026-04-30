import { clueBank } from './crossword-clues.js';

function seededRng(seed) {
  let h = 0xdeadbeef ^ seed;
  return () => {
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    h = (h ^ (h >>> 16)) >>> 0;
    return h / 4294967296;
  };
}

function hashStr(str) {
  let h = 0xdeadbeef;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 2654435761);
    h = (h << 13) | (h >>> 19);
  }
  return (h ^ (h >>> 16)) >>> 0;
}

function shuffle(arr, rng) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const allWords = Object.keys(clueBank);
const SIZE = 8;

function createEmptyGrid() {
  return Array.from({ length: SIZE }, () => Array(SIZE).fill(''));
}

function canPlace(grid, word, row, col, isAcross, placed) {
  const len = word.length;
  const dr = isAcross ? 0 : 1;
  const dc = isAcross ? 1 : 0;

  // Check bounds
  if (row + dr * (len - 1) >= SIZE || col + dc * (len - 1) >= SIZE) return false;

  // Check cell before word is empty or edge
  const br = row - dr, bc = col - dc;
  if (br >= 0 && br < SIZE && bc >= 0 && bc < SIZE && grid[br][bc] !== '') return false;

  // Check cell after word is empty or edge
  const ar = row + dr * len, ac = col + dc * len;
  if (ar >= 0 && ar < SIZE && ac >= 0 && ac < SIZE && grid[ar][ac] !== '') return false;

  let hasIntersection = placed.length === 0; // First word doesn't need intersection

  for (let i = 0; i < len; i++) {
    const r = row + dr * i;
    const c = col + dc * i;
    const cell = grid[r][c];

    if (cell !== '') {
      // Cell already has a letter — must match
      if (cell !== word[i]) return false;
      hasIntersection = true;
    } else {
      // Cell is empty — check adjacent cells perpendicular to our direction
      // to avoid creating unintended adjacent words
      if (isAcross) {
        if (r > 0 && grid[r - 1][c] !== '') return false;
        if (r < SIZE - 1 && grid[r + 1][c] !== '') return false;
      } else {
        if (c > 0 && grid[r][c - 1] !== '') return false;
        if (c < SIZE - 1 && grid[r][c + 1] !== '') return false;
      }
    }
  }

  return hasIntersection;
}

function placeWord(grid, word, row, col, isAcross) {
  const dr = isAcross ? 0 : 1;
  const dc = isAcross ? 1 : 0;
  for (let i = 0; i < word.length; i++) {
    grid[row + dr * i][col + dc * i] = word[i];
  }
}

function removeWord(grid, word, row, col, isAcross, snapshot) {
  const dr = isAcross ? 0 : 1;
  const dc = isAcross ? 1 : 0;
  for (let i = 0; i < word.length; i++) {
    const r = row + dr * i, c = col + dc * i;
    grid[r][c] = snapshot[i];
  }
}

function getSnapshot(grid, word, row, col, isAcross) {
  const dr = isAcross ? 0 : 1;
  const dc = isAcross ? 1 : 0;
  return Array.from({ length: word.length }, (_, i) => grid[row + dr * i][col + dc * i]);
}

export function generatePuzzle(dateStr) {
  const rng = seededRng(hashStr('xw4:' + dateStr));
  const wordList = shuffle(allWords.filter(w => w.length >= 3 && w.length <= 6), rng);

  const grid = createEmptyGrid();
  const placed = []; // {word, row, col, isAcross}
  const usedWords = new Set();

  // Place 8-12 words
  const targetWords = 8 + Math.floor(rng() * 5);

  for (const word of wordList) {
    if (placed.length >= targetWords) break;
    if (usedWords.has(word)) continue;

    // Try all positions and directions
    const positions = [];
    for (let isAcross = 0; isAcross <= 1; isAcross++) {
      for (let r = 0; r < SIZE; r++) {
        for (let c = 0; c < SIZE; c++) {
          if (canPlace(grid, word, r, c, !!isAcross, placed)) {
            // Score: prefer intersections
            const dr = isAcross ? 0 : 1;
            const dc = isAcross ? 1 : 0;
            let intersections = 0;
            for (let i = 0; i < word.length; i++) {
              if (grid[r + dr * i][c + dc * i] !== '') intersections++;
            }
            positions.push({ r, c, isAcross: !!isAcross, intersections });
          }
        }
      }
    }

    if (positions.length === 0) continue;

    // Prefer positions with more intersections
    positions.sort((a, b) => b.intersections - a.intersections);
    const best = positions.slice(0, 3);
    const pick = best[Math.floor(rng() * best.length)];

    const snap = getSnapshot(grid, word, pick.r, pick.c, pick.isAcross);
    placeWord(grid, word, pick.r, pick.c, pick.isAcross);
    placed.push({ word, row: pick.r, col: pick.c, isAcross: pick.isAcross });
    usedWords.add(word);
  }

  if (placed.length < 6) {
    // Not enough words placed, retry with different seed
    return generatePuzzle(dateStr + 'retry');
  }

  // Trim grid to bounding box
  let minR = SIZE, maxR = 0, minC = SIZE, maxC = 0;
  for (let r = 0; r < SIZE; r++) {
    for (let c = 0; c < SIZE; c++) {
      if (grid[r][c] !== '') {
        minR = Math.min(minR, r); maxR = Math.max(maxR, r);
        minC = Math.min(minC, c); maxC = Math.max(maxC, c);
      }
    }
  }

  const rows = maxR - minR + 1;
  const cols = maxC - minC + 1;
  const trimmedGrid = [];
  for (let r = minR; r <= maxR; r++) {
    const row = [];
    for (let c = minC; c <= maxC; c++) {
      row.push(grid[r][c] !== '' ? grid[r][c].toUpperCase() : null);
    }
    trimmedGrid.push(row);
  }

  // Assign clue numbers
  let num = 1;
  const numberMap = {}; // "r:c" → number
  const across = [];
  const down = [];

  // Find all word starts
  for (const p of placed) {
    const adjR = p.row - minR;
    const adjC = p.col - minC;
    const key = `${adjR}:${adjC}`;
    if (!numberMap[key]) numberMap[key] = num++;
  }

  for (const p of placed) {
    const adjR = p.row - minR;
    const adjC = p.col - minC;
    const key = `${adjR}:${adjC}`;
    const entry = {
      number: numberMap[key],
      clue: clueBank[p.word],
      row: adjR,
      col: adjC,
      length: p.word.length,
    };
    if (p.isAcross) across.push(entry);
    else down.push(entry);
  }

  across.sort((a, b) => a.row * 100 + a.col - (b.row * 100 + b.col));
  down.sort((a, b) => a.row * 100 + a.col - (b.row * 100 + b.col));

  return { grid: trimmedGrid, across, down, rows, cols };
}

export async function getOrCreateDailyPuzzle(db, dateStr) {
  const row = await db.prepare('SELECT grid, clues_across, clues_down FROM crossword_puzzles WHERE date = ?').bind(dateStr).first();
  if (row) return { grid: JSON.parse(row.grid), across: JSON.parse(row.clues_across), down: JSON.parse(row.clues_down) };

  const puzzle = generatePuzzle(dateStr);
  await db.prepare('INSERT OR IGNORE INTO crossword_puzzles (date, grid, clues_across, clues_down) VALUES (?, ?, ?, ?)')
    .bind(dateStr, JSON.stringify(puzzle.grid), JSON.stringify(puzzle.across), JSON.stringify(puzzle.down)).run();
  return puzzle;
}
