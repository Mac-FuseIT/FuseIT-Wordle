// Seeded PRNG (mulberry32)
function mulberry32(seed) {
  return function() {
    seed |= 0; seed = seed + 0x6D2B79F5 | 0;
    let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

// Convert date string to numeric seed
function dateToSeed(dateStr) {
  let hash = 0;
  for (let i = 0; i < dateStr.length; i++) {
    const chr = dateStr.charCodeAt(i);
    hash = ((hash << 5) - hash) + chr;
    hash |= 0;
  }
  return Math.abs(hash);
}

// Generate the deck for a given date
function generateDeck(dateStr) {
  const suits = ['h', 'd', 'c', 's'];
  const ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
  const deck = [];
  for (const suit of suits) {
    for (const rank of ranks) {
      deck.push(rank + suit);
    }
  }
  // Fisher-Yates shuffle with seeded RNG
  const rng = mulberry32(dateToSeed(dateStr));
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

// Deal into initial game state
function dealGame(dateStr) {
  const deck = generateDeck(dateStr);
  const tableau = [];
  let idx = 0;
  for (let col = 0; col < 7; col++) {
    const hidden = deck.slice(idx, idx + col);
    idx += col;
    const visible = [deck[idx]];
    idx++;
    tableau.push({ hidden, visible });
  }
  // Remaining 24 cards go to stock
  const stock = deck.slice(idx);
  return {
    stock,
    waste: [],
    foundations: { hearts: [], diamonds: [], clubs: [], spades: [] },
    tableau,
    moves: 0,
    status: 'in_progress',
    drawPointer: 0,
    reserve: null
  };
}

export { mulberry32, dateToSeed, generateDeck, dealGame };
