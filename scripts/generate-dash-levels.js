#!/usr/bin/env node
// Usage: node scripts/generate-dash-levels.js --days 30 --start 2026-05-07
// Outputs wrangler d1 execute commands to insert levels into D1.

const args = process.argv.slice(2);
const daysArg = args.indexOf('--days');
const startArg = args.indexOf('--start');
const DAYS = daysArg >= 0 ? parseInt(args[daysArg + 1]) : 30;
const START = startArg >= 0 ? args[startArg + 1] : new Date().toISOString().slice(0, 10);

const W = 150, H = 12;
const TILE = { AIR: 0, GROUND: 1, BRICK: 2, QUESTION: 3, SOLID: 4, PIPE_TOP: 5, PIPE_BODY: 6, COIN: 7, PLATFORM: 8, SPIKE: 9, LAVA: 10, FLAG: 11, SPRING: 13, ICE: 14 };
const ZONE_NAMES = ['grassland', 'underground', 'sky', 'desert', 'castle'];

// Mulberry32 seeded RNG
function mulberry32(seed) {
  return function () {
    seed |= 0; seed = seed + 0x6D2B79F5 | 0;
    let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

function dateToSeed(dateStr) {
  return dateStr.split('-').reduce((acc, n) => acc * 100 + parseInt(n), 0);
}

function addDays(dateStr, n) {
  const d = new Date(dateStr + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

function generateLevel(dateStr) {
  const rng = mulberry32(dateToSeed(dateStr));
  const ri = (min, max) => Math.floor(rng() * (max - min + 1)) + min;
  const rb = (p = 0.5) => rng() < p;

  // Init grid: all air
  const tiles = Array.from({ length: H }, () => new Array(W).fill(TILE.AIR));

  // Fill bottom 2 rows with ground
  for (let c = 0; c < W; c++) {
    tiles[H - 1][c] = TILE.GROUND;
    tiles[H - 2][c] = TILE.GROUND;
  }

  const enemies = [];
  const movingPlatforms = [];
  const warpPipes = [];
  const questionBlocks = [];

  // Zone themes
  const zoneTheme = ZONE_NAMES[Math.floor(rng() * ZONE_NAMES.length)];

  // 5 zones, each 30 cols wide
  for (let zone = 0; zone < 5; zone++) {
    const zoneStart = zone * 30 + 2;
    const zoneEnd = zoneStart + 28;

    // Pick 2 challenge types
    const challenges = [];
    const allChallenges = ['platforms', 'gaps', 'pipes', 'enemies', 'coins', 'bricks', 'question', 'spikes', 'moving', 'vertical'];
    while (challenges.length < 2) {
      const c = allChallenges[ri(0, allChallenges.length - 1)];
      if (!challenges.includes(c)) challenges.push(c);
    }

    for (const ch of challenges) {
      switch (ch) {
        case 'gaps': {
          // Create 1-2 gaps in ground
          const gapCount = ri(1, 2);
          for (let g = 0; g < gapCount; g++) {
            const gapCol = ri(zoneStart + 2, zoneEnd - 4);
            const gapWidth = ri(2, 4);
            for (let c = gapCol; c < Math.min(gapCol + gapWidth, zoneEnd); c++) {
              tiles[H - 1][c] = TILE.AIR;
              tiles[H - 2][c] = TILE.AIR;
              if (zone >= 3) tiles[H - 1][c] = TILE.LAVA; // lava in later zones
            }
          }
          break;
        }
        case 'platforms': {
          const count = ri(2, 4);
          for (let i = 0; i < count; i++) {
            const col = ri(zoneStart, zoneEnd - 4);
            const row = ri(H - 6, H - 4);
            const len = ri(2, 4);
            for (let c = col; c < Math.min(col + len, zoneEnd); c++) {
              tiles[row][c] = TILE.PLATFORM;
            }
          }
          break;
        }
        case 'bricks': {
          const row = ri(H - 6, H - 4);
          for (let c = zoneStart; c < zoneEnd; c += ri(1, 3)) {
            if (rng() < 0.5) tiles[row][c] = TILE.BRICK;
          }
          break;
        }
        case 'question': {
          const row = H - 5;
          for (let c = zoneStart + 2; c < zoneEnd - 2; c += ri(3, 5)) {
            tiles[row][c] = TILE.QUESTION;
            const contents = ['coin', 'coin', 'coin', 'mushroom', 'fireFlower', 'star'];
            questionBlocks.push({ x: c, y: row, content: contents[ri(0, contents.length - 1)] });
          }
          break;
        }
        case 'coins': {
          const row = ri(H - 6, H - 4);
          for (let c = zoneStart; c < zoneEnd; c++) {
            if (rng() < 0.3) tiles[row][c] = TILE.COIN;
          }
          break;
        }
        case 'pipes': {
          const col = ri(zoneStart + 2, zoneEnd - 4);
          const pipeH = ri(2, 3);
          for (let r = H - 2 - pipeH; r < H - 2; r++) {
            tiles[r][col] = r === H - 2 - pipeH ? TILE.PIPE_TOP : TILE.PIPE_BODY;
            tiles[r][col + 1] = r === H - 2 - pipeH ? TILE.PIPE_TOP : TILE.PIPE_BODY;
          }
          // Add warp pipe if zone 1 or 2
          if (zone <= 2 && warpPipes.length < 2) {
            const exitZone = zone + 1;
            const exitCol = exitZone * 30 + ri(5, 20);
            warpPipes.push({ entrance: { x: col, y: H - 2 - pipeH }, exit: { x: exitCol, y: H - 3 } });
          }
          break;
        }
        case 'enemies': {
          const types = zone === 0 ? ['goomba'] :
                        zone === 1 ? ['goomba', 'buzzyBeetle'] :
                        zone === 2 ? ['koopa', 'spiny'] :
                        zone === 3 ? ['spiny', 'koopa'] :
                        ['hammerBro', 'koopa', 'boo'];
          const count = ri(2, 4);
          for (let i = 0; i < count; i++) {
            const col = ri(zoneStart + 2, zoneEnd - 2);
            enemies.push({ type: types[ri(0, types.length - 1)], x: col, y: H - 3 });
          }
          break;
        }
        case 'spikes': {
          const col = ri(zoneStart + 2, zoneEnd - 4);
          const len = ri(2, 4);
          for (let c = col; c < Math.min(col + len, zoneEnd - 1); c++) {
            tiles[H - 3][c] = TILE.SPIKE;
          }
          break;
        }
        case 'moving': {
          const col = ri(zoneStart + 2, zoneEnd - 6);
          const row = ri(H - 6, H - 4);
          movingPlatforms.push({ x: col, y: row, width: ri(2, 3), axis: rb() ? 'x' : 'y', range: ri(3, 5), speed: rng() * 1.5 + 0.5 });
          break;
        }
        case 'vertical': {
          // Staircase of platforms going up
          let col = zoneStart + 2;
          for (let step = 0; step < 4; step++) {
            const row = H - 3 - step * 2;
            if (row >= 2) {
              tiles[row][col] = TILE.PLATFORM;
              tiles[row][col + 1] = TILE.PLATFORM;
            }
            col += 3;
          }
          break;
        }
      }
    }

    // Scatter some coins along ground level
    for (let c = zoneStart; c < zoneEnd; c++) {
      if (rng() < 0.15 && tiles[H - 3][c] === TILE.AIR) {
        tiles[H - 3][c] = TILE.COIN;
      }
    }
  }

  // Ensure start area is clear (cols 0-4)
  for (let r = 0; r < H - 2; r++) {
    for (let c = 0; c < 4; c++) {
      if (tiles[r][c] !== TILE.GROUND) tiles[r][c] = TILE.AIR;
    }
  }

  // Place flag pole at col 147-148
  for (let r = H - 6; r < H - 2; r++) {
    tiles[r][148] = TILE.FLAG;
  }
  // Solid ground under flag
  tiles[H - 2][148] = TILE.GROUND;
  tiles[H - 1][148] = TILE.GROUND;

  return {
    width: W,
    height: H,
    tiles,
    enemies,
    movingPlatforms,
    warpPipes,
    questionBlocks,
    zoneName: zoneTheme,
  };
}

// Generate and output SQL insert commands
const lines = [];
for (let i = 0; i < DAYS; i++) {
  const date = addDays(START, i);
  const level = generateLevel(date);
  const json = JSON.stringify(level).replace(/'/g, "''");
  const createdAt = new Date().toISOString();
  lines.push(`INSERT OR IGNORE INTO dash_levels (date, level_data, created_at) VALUES ('${date}', '${json}', '${createdAt}');`);
}

// Output as a single wrangler d1 execute command
const sqlFile = `/tmp/dash_levels_${START}.sql`;
const fs = require('fs');
fs.writeFileSync(sqlFile, lines.join('\n') + '\n');
console.log(`Generated ${DAYS} levels starting from ${START}`);
console.log(`SQL written to: ${sqlFile}`);
console.log(`\nRun the following to insert into D1:`);
console.log(`  npx wrangler d1 execute fuseit-wordle-db --file=${sqlFile} --remote`);
