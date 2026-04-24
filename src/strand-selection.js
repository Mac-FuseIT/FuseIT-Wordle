const ROWS = 8, COLS = 6, TOTAL = 48;

const wordPool = {
  8: ["abstract","allocate","automate","backbone","callback","compiler","consumer","database","debugger","decorate",
      "dispatch","document","emulator","endpoint","evaluate","executor","explorer","failover","fastboot","firewall",
      "firmware","frontend","function","generate","graphite","hardware","hashcode","headless","hostname","instance",
      "iterator","keyboard","keystore","language","listener","manifest","metadata","microapp","monolith","mutation",
      "notebook","observer","operator","optimize","overflow","pipeline","platform","playbook","postgres","profiler",
      "protocol","provider","readonly","redirect","refactor","register","renderer","resource","response","rollback",
      "scaffold","security","selector","sequence","shutdown","simulate","snapshot","software","splitter","standard",
      "strategy","template","terminal","throttle","topology","tracking","transfer","traverse","tutorial","unittest",
      "validate","variable","viewport","watchdog","workflow"],
  7: ["ansible","backend","binding","bitwise","blocker","boolean","browser","builder","caching","cluster",
      "codegen","compile","compose","compute","console","context","control","convert","counter","cypress",
      "decoder","default","desktop","digital","discord","dynamic","elastic","encrypt","express","factory",
      "feature","flutter","gateway","generic","grafana","handler","haskell","hosting","integer","jenkins",
      "jupyter","keyword","library","logging","mapping","marshal","metrics","migrate","monitor","network",
      "package","payload","pointer","postman","process","program","project","promise","publish","reactor",
      "reducer","runtime","sandbox","scanner","scraper","service","servlet","session","setting","startup",
      "storage","swagger","testing","toolbar","trigger","upgrade","vagrant","version","webhook","webpack","wrapper"],
  6: ["deploy","docker","kernel","lambda","linter","logger","module","parser","plugin","portal","router",
      "schema","script","server","shader","signal","socket","source","sphinx","sprint","static","stream",
      "struct","subnet","svelte","switch","syntax","syslog","tensor","thread","toggle","tracer","tunnel",
      "update","upload","vector","widget","wizard"],
  5: ["stack","queue","array","cache","debug","merge","patch","clone","fetch","parse","query","route",
      "scope","shell","token","trait","build","class","const","float","index","input","model","print",
      "state","store","throw","value","watch","write","yield","async","batch","chain","chunk","codec",
      "crate","delta","embed","epoch","event","flask","frame","graph","guard","hooks","hydra","hyper",
      "infer","kafka","layer","login","macro","maven","mixin","mocha","mutex","nexus","nginx","oauth",
      "pivot","prism","proxy","rails","react","redis","regex","relay","retry","shard","slack","spawn",
      "split","squid","stash","swift","torch","trace","trunk","typed","vault","viper"],
  4: ["bash","byte","char","code","cron","curl","dart","diff","disk","docs","dump","edit","enum","eval",
      "exec","flag","flex","flux","font","fork","func","fuse","fuzz","gist","glob","grep","guid","gzip",
      "hack","hash","helm","hook","host","html","http","icon","info","init","java","jest","json","kern",
      "keys","kube","lang","link","lint","lisp","load","lock","logs","loop","main","make","math","mesh",
      "meta","mock","node","null","opts","pack","ping","pipe","pods","poll","port","proc","prod","prop",
      "pull","push","raft","rake","repl","repo","root","rust","saas","sass","scan","seed","slug","smtp",
      "sort","spec","stub","sudo","swap","sync","tabs","task","tech","temp","test","tick","toml","tree",
      "trie","type","undo","unix","uuid","void","wasm","wiki","yaml","yarn"],
  3: []
};

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

const DIRS = [[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]];

function findPath(grid, letters, idx, r, c, visited, rng) {
  if (r < 0 || r >= ROWS || c < 0 || c >= COLS) return null;
  const key = `${r}:${c}`;
  if (visited.has(key)) return null;
  if (grid[r][c] !== null) return null; // cell already used

  if (idx === letters.length - 1) {
    return [[r, c]];
  }

  visited.add(key);
  const dirs = shuffle([...DIRS], rng);
  for (const [dr, dc] of dirs) {
    const rest = findPath(grid, letters, idx + 1, r + dr, c + dc, visited, rng);
    if (rest) return [[r, c], ...rest];
  }
  visited.delete(key);
  return null;
}

function tryPlaceWord(grid, word, rng) {
  const letters = word.toUpperCase().split('');
  // Collect all empty cells as potential starts
  const starts = [];
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      if (grid[r][c] === null) starts.push([r, c]);
    }
  }
  const shuffled = shuffle(starts, rng);

  for (const [sr, sc] of shuffled.slice(0, 40)) {
    const path = findPath(grid, letters, 0, sr, sc, new Set(), rng);
    if (path) return path;
  }
  return null;
}

function placeOnGrid(grid, word, path) {
  const letters = word.toUpperCase().split('');
  path.forEach(([r, c], i) => { grid[r][c] = letters[i]; });
}

function countEmpty(grid) {
  let n = 0;
  for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) if (grid[r][c] === null) n++;
  return n;
}

export function generateStrandPuzzle(dateStr) {
  const rng = seededRng(hashStr('gram2:' + dateStr));

  // Try multiple times to fill the entire grid
  for (let attempt = 0; attempt < 10; attempt++) {
    const grid = Array.from({ length: ROWS }, () => Array(COLS).fill(null));
    const placedWords = [];

    // 1. Place one 8-letter word first (the "spangram" equivalent)
    const eights = shuffle(wordPool[8], rng);
    let placed8 = false;
    for (const w of eights.slice(0, 20)) {
      const path = tryPlaceWord(grid, w, rng);
      if (path) {
        placeOnGrid(grid, w, path);
        placedWords.push({ word: w.toUpperCase(), path });
        placed8 = true;
        break;
      }
    }
    if (!placed8) continue;

    // 2. Fill remaining cells with words, largest first
    let remaining = countEmpty(grid);
    let stuck = 0;

    while (remaining > 0 && stuck < 50) {
      // Pick word length that fits
      let targetLens;
      if (remaining >= 8) targetLens = [7, 6, 5, 8];
      else if (remaining >= 7) targetLens = [7, 6, 5];
      else if (remaining >= 6) targetLens = [6, 5, 4];
      else if (remaining >= 5) targetLens = [5, 4];
      else if (remaining >= 4) targetLens = [4];
      else break; // can't fit a 4+ letter word

      let placedOne = false;
      for (const len of targetLens) {
        const pool = wordPool[len];
        if (!pool) continue;
        const candidates = shuffle(pool, rng);
        const usedWords = new Set(placedWords.map(p => p.word));

        for (const w of candidates.slice(0, 40)) {
          if (usedWords.has(w.toUpperCase())) continue;
          const path = tryPlaceWord(grid, w, rng);
          if (path) {
            placeOnGrid(grid, w, path);
            placedWords.push({ word: w.toUpperCase(), path });
            placedOne = true;
            break;
          }
        }
        if (placedOne) break;
      }

      if (!placedOne) stuck++;
      remaining = countEmpty(grid);
    }

    if (remaining <= 3) {
      // Leave remaining cells empty (blocked)
      const finalGrid = grid.map(row => row.map(c => c || null));
      return { grid: finalGrid, words: placedWords };
    }
  }

  // Fallback — fill remaining with single letters as 3-letter combos
  // This shouldn't happen often with a good word pool
  const grid = Array.from({ length: ROWS }, () => Array(COLS).fill(null));
  const placedWords = [];
  const allWords = shuffle([...wordPool[5], ...wordPool[4]], rng);
  for (const w of allWords) {
    if (countEmpty(grid) === 0) break;
    const path = tryPlaceWord(grid, w, rng);
    if (path) {
      placeOnGrid(grid, w, path);
      placedWords.push({ word: w.toUpperCase(), path });
    }
  }
  // Fill any remaining as blocked
  const finalGrid = grid.map(row => row.map(c => c || null));
  return { grid: finalGrid, words: placedWords };
}

export async function getOrCreateDailyStrand(db, dateStr) {
  const row = await db.prepare('SELECT grid, theme, spangram, theme_words FROM strand_puzzles WHERE date = ?').bind(dateStr).first();
  if (row) {
    const words = JSON.parse(row.theme_words);
    return { grid: JSON.parse(row.grid), words };
  }

  const puzzle = generateStrandPuzzle(dateStr);
  await db.prepare('INSERT OR IGNORE INTO strand_puzzles (date, grid, theme, spangram, theme_words) VALUES (?, ?, ?, ?, ?)')
    .bind(dateStr, JSON.stringify(puzzle.grid), '', '{}', JSON.stringify(puzzle.words)).run();
  return puzzle;
}
