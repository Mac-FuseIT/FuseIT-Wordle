import { wordsByLength } from './words.js';

// MurmurHash3-inspired mixer — same as word-selection.js for consistency
function hash(str) {
  let h = 0xdeadbeef;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 2654435761);
    h = (h << 13) | (h >>> 19);
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507);
  h = Math.imul(h ^ (h >>> 13), 3266489909);
  return (h ^ (h >>> 16)) >>> 0;
}

export function getChainItPuzzle(dateStr) {
  // Pick length: 4, 5, or 6
  // Weighted length selection: 50% = 4 letters, 40% = 5 letters, 10% = 6 letters
  const lengthHash = hash('chainit-length:' + dateStr);
  const roll = lengthHash % 100;
  const wordLength = roll < 50 ? 4 : (roll < 90 ? 5 : 6);

  // Filter to only real English words — eliminates tech acronyms (GRPC, CSRF,
  // SMTP, NUXTJS, REGEXP etc.) that aren't in standard dictionaries and have
  // no valid 1-letter neighbours in a word ladder.
  //
  // Strategy: blocklist of known tech-only terms that pass heuristic filters,
  // combined with pattern rules for structural non-English indicators.
  //
  // Rules applied in order:
  //   1. Blocklist — tech acronyms/tools that are NOT in dictionaryapi.dev
  //   2. At least 1 vowel (drops grpc, csrf, smtp, nmap, ctrl …)
  //   3. No 4+ consecutive consonants (drops nuxtjs …)
  //   4. No 3+ consecutive consonants for 4-letter words (drops json, ctrl …)
  //   5. No 'x' followed by a consonant — catches regexp (xp), nuxtjs (xtj) etc.
  //      English words like "boxer", "oxide", "exact" have x before a vowel.
  //   6. Ends with known tech-only suffixes that are never English word endings
  const techOnlyWords = new Set([
    // 4-letter tech acronyms / tools — definitely not in standard dictionaries
    'ajax','amqp','ansi','args','bios','cicd','cron','csrf','ctrl','deps',
    'devs','dhcp','dkim','enum','eval','exec','fifo','func','glob','goto',
    'grep','grpc','guid','gzip','html','http','imap','init','ipfs','jira',
    'jest','json','kube','ldap','lifo','lint','lisp','llvm','mern','mqtt',
    'nats','nmap','noop','orms','proc','prod','prom','prop','repl','repo',
    'saas','sass','scsi','smtp','snmp','sram','stub','sudo','sync','toml',
    'trie','undo','unix','uuid','vlan','wasm','wget','xmpp','yaml','zlib',
    // 5-letter tech-only (one-vowel real-word false positives handled by blocklist)
    'async','azure','babel','codec','cname','const','crate','deque','devex',
    'dtype','enums','nginx','oauth','redux','regex','scala','svelt','xpath',
    'pydoc',
    // 6-letter tech-only
    'devops','docker','github','gitlab','golang','groovy','heroku','jython',
    'jquery','kotlin','mongod','nestjs','nodejs','nuxtjs','prisma','python',
    'regexp','svelte','syslog','vercel','vuexjs','vscode','webkit','vulkan',
    'erlang','django',
  ]);

  const allWords = wordsByLength[wordLength];
  const words = (allWords || []).filter(w => {
    // 1. Explicit blocklist
    if (techOnlyWords.has(w)) return false;

    const vowelCount = (w.match(/[aeiou]/g) || []).length;

    // 2. Must have at least 1 vowel
    if (vowelCount < 1) return false;

    // 3. No 4+ consecutive consonants
    if (/[^aeiou]{4}/.test(w)) return false;

    // 4. No 3+ consecutive consonants for 4-letter words
    if (wordLength <= 4 && /[^aeiou]{3}/.test(w)) return false;

    // 5. No 'x' followed by a consonant — key rule that catches regexp, nuxtjs etc.
    //    Valid English: boxer (x+e), exact (x+a), oxide (x+i).
    //    Invalid: regexp (x+p), nexus passes fine (x+u).
    if (/x[^aeiou]/.test(w)) return false;

    // 6. Ends with known tech-only suffixes (never standard English endings)
    if (/(?:js|db|fs|ql|rx)$/.test(w)) return false;

    return true;
  });
  if (!words || words.length < 2) return null;

  // Pick target word
  const targetHash = hash('chainit-target:' + dateStr);
  const targetIndex = targetHash % words.length;
  const targetWord = words[targetIndex];

  // Pick start word (different from target)
  const startHash = hash('chainit-start:' + dateStr);
  let startIndex = startHash % words.length;
  if (startIndex === targetIndex) {
    startIndex = (startIndex + 1) % words.length;
  }
  const startWord = words[startIndex];

  return { startWord, targetWord, length: wordLength };
}

export async function getOrCreateChainItPuzzle(db, dateStr) {
  // Check if puzzle already cached in DB
  const row = await db.prepare(
    'SELECT start_word, target_word, length FROM chainit_puzzles WHERE date = ?'
  ).bind(dateStr).first();

  if (row) return row;

  // Generate and cache
  const puzzle = getChainItPuzzle(dateStr);
  if (!puzzle) return null;

  await db.prepare(
    'INSERT OR IGNORE INTO chainit_puzzles (date, start_word, target_word, length) VALUES (?, ?, ?, ?)'
  ).bind(dateStr, puzzle.startWord, puzzle.targetWord, puzzle.length).run();

  return { start_word: puzzle.startWord, target_word: puzzle.targetWord, length: puzzle.length };
}
