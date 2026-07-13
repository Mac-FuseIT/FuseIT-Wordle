## Developer Notes — Fix word selection in generate-strands.mjs

### Files Created
- none

### Files Modified
- `scripts/generate-strands.mjs` — replaced both Datamuse fetch functions and updated call site + delay

### Key Decisions

**fetchSpangramCandidates rewrite:**
- Old approach: `ml=<topic>` (word2vec means-like) + `rel_trg`. word2vec follows loose semantic chains and can return unrelated words ("spiders" → "chicken" via fear/phobia path).
- New approach: 6 parallel queries. Tier 1 uses WordNet-backed relations (rel_syn, rel_spc, rel_gen, rel_com) which are structurally anchored to the topic. Tier 2 uses corpus signals with an explicit `topics=` hint (rel_jjb, rel_trg) for breadth.
- Scoring: WordNet signals weight 600–1000; corpus signals weight 300–400. Words appearing in 2+ sources get a 3× multiplier to reward intersection.
- Frequency gate: `freq < 1.5` filters obscure words early.
- Fallback: if WordNet returns < 3 candidates (e.g. rare topic), falls back to constrained ml+topics query.
- Singular stripping (`topic.replace(/s$/, '')`) improves WordNet lookup hit rate.

**fetchWordsForSpangram rewrite:**
- Added `topics=${topic}` hint to ml and rel_trg queries — keeps fill words in the theme's ballpark.
- Added rel_jjb (adjectives describing the spangram) and rel_gen (hyponyms of the spangram) as additional signals, each with fixed score bonuses (30000, 40000) to compete with high ml scores.
- rel_gen uses a looser freq gate (2.0 vs 3.0) since hyponyms tend to be more specific words.

**Call site:**
- `fetchWordsForSpangram(spangram, topic)` — topic now threaded through so the API can bias results.

**Delay:**
- Increased 150ms → 250ms to avoid rate-limiting with the higher number of concurrent API calls per spangram attempt.

### Library Docs Consulted (Context7)
- none (Datamuse is a plain HTTP REST API, no SDK involved)

### Build & Test Results
```
node --check scripts/generate-strands.mjs
SYNTAX OK
```

### Open Issues
- The singular stripping `topic.replace(/s$/, '')` is naive — "octopus" → "octopu". A proper stemmer would help but adds a dependency. For now the fallback path handles edge cases.
- Word frequency thresholds (1.5 for spangrams, 3.0 for fill) were carried over from the original code. May need tuning after live testing.

---

## Developer Notes — fix-spangram: topic word as spangram

### Files Modified
- `scripts/generate-strands.mjs` — replaced `fetchSpangramCandidates` and `fetchWordsForSpangram`

### Key Decisions

**fetchSpangramCandidates — topic-first approach:**
- Old approach: queried all 6 Datamuse signals (rel_syn, rel_spc, rel_gen, rel_com, rel_jjb, rel_trg) and scored/ranked them to pick the "best" related spangram word. This meant the spangram was always a *different* word from the topic.
- New approach: if the topic itself is 6–8 all-alpha letters, return it immediately as the only candidate. The spangram IS the topic (e.g. "spiders", "octopus", "pirates").
- Also checks singular form (`topic.replace(/s$/, '')`) — e.g. "insects" → try "insect" (6 letters, valid).
- Only falls back to API queries when the topic is too short (<6) or too long (>8) letters.
- Fallback queries: rel_syn + rel_spc + rel_gen for both topic and singular form in parallel, filtered to 6–8 letter words with freq ≥ 1.0.
- Last resort: ml+topics query if still empty, freq ≥ 2.0, capped at 5 candidates.

**fetchWordsForSpangram — topic-anchored filler words:**
- Old approach: queried Datamuse using the *spangram word* as the query target. When spangram ≠ topic, filler words could drift away from the theme.
- New approach: always uses the *topic* as the primary query word (both for `ml=` and `rel_*` params). Since spangram ≈ topic, this keeps fillers tightly anchored to the theme's meaning.
- Uses `queryWord = topic` and `singular = queryWord.replace(/s$/, '')` consistently.
- Excludes both spangram, topic, AND singular from scored results to avoid near-duplicates.
- Lowered freq gate to 2.0 (from 3.0) for all result types — more inclusive, lets the scoring bonuses do the ranking.
- Scoring bonuses: trgRes +50000, genRes +60000, comRes +40000, jjbRes +30000 (same structure as before).

**Call site:** unchanged — `fetchWordsForSpangram(spangram, topic)` already passes topic.

### Library Docs Consulted (Context7)
- none (Datamuse plain REST API)

### Build & Test Results
```
node --check scripts/generate-strands.mjs
SYNTAX OK
```
Committed: `fix: use topic word itself as spangram, fetch fillers from topic` (db745fc) on `feat/fix-word-selection`

### Open Issues
- Naive singular stripping still applies (e.g. "octopus" → "octopu"). Since octopus IS 7 letters and all-alpha, it returns directly without stripping, so no issue there. Only affects the fallback path for short/long topics.
- Some short topics (ocean=5, space=5, art=3) will need a synonym. "ocean" → likely finds "waters", "marine" etc. "art" → harder, may return few candidates. Should be monitored in live runs.

---

## Developer Notes — fix-scoring: proper noun filtering and fixed bonuses in fetchWordsForSpangram

### Files Modified
- `scripts/generate-strands.mjs` — replaced `fetchWordsForSpangram` with fixed-bonus scoring and proper noun filtering

### Key Decisions

**Root cause:** Datamuse `ml` (means-like / word2vec) returns raw `w.score` values in the 50000–90000+ range for words like "virginia" (Virginia deer) and "mountain" (mountain deer). These raw scores dwarfed the fixed bonuses applied to tighter signals (trgRes +50000, genRes +60000), so proper nouns and generic words beat genuinely related words like "antler", "fawn", "stag".

**Fix — stop using `w.score` from ml results:**
- Old: `scored[word] = (scored[word] || 0) + (w.score || 0) + bonus` — adds the raw Datamuse word2vec score.
- New: `scored[word] = (scored[word] || 0) + bonus` — ignores `w.score` entirely. Only the fixed bonus per source tier matters.

**Fix — proper noun filtering:**
- Added `isProperNoun(w)` check: skips words where `w.tags` contains `'prop'` (Datamuse proper noun tag) OR where the word starts with an uppercase letter. Both conditions independently catch cases like "Virginia", "Kingston".
- Added `md=f,p` to all API URLs (was `md=f`) — the `p` flag enables part-of-speech tags in the response so `'prop'` is actually returned.

**Fix — rebalanced bonuses:**
- Old: ml=0 (relied on raw score), trg=50000, gen=60000, com=40000, jjb=30000
- New: gen=100000, com=90000, trg=80000, jjb=70000, ml=10000 (flat fallback)
- Tight WordNet/corpus signals now always dominate. ml words only enter the pool as low-confidence fallbacks.

**Multi-source bonus:**
- Added signal counting across all 5 result arrays. Words appearing in 2+ sources get ×1.5; 3+ sources get ×2. This rewards high-confidence words that multiple Datamuse endpoints agree on.

### Library Docs Consulted (Context7)
- none (Datamuse plain REST API)

### Build & Test Results
```
node --check scripts/generate-strands.mjs
SYNTAX OK
```
Committed: `fix: replace ml raw score with fixed bonuses, filter proper nouns in fetchWordsForSpangram` (c2bbb70) on `feat/fix-word-selection`

### Open Issues
- none

## Developer Notes — Strict spangram selection (fix-strict-spangram)

### Files Modified
- `scripts/generate-strands.mjs` — Replaced `fetchSpangramCandidates` with a stricter version

### Key Decisions
The old function queried `rel_syn`, `rel_spc`, `rel_gen`, and `ml` in parallel when the topic didn't fit 6–8 letters. `rel_spc` (specific) and `rel_gen` (general) are hypernym/hyponym relations that easily drift off-topic — e.g. "hives" → `rel_spc` → "eruption" (skin hives, not bee hives). `ml` (means like) is even broader.

New strategy, in priority order:
1. Topic itself if 6–8 letters — always the best spangram
2. Singular form (strip trailing `s`) if that fits
3. Plural form (append `s`) if topic is exactly 5 letters and no candidate yet
4. Only if still empty: `rel_syn` (exact synonyms) with `freq >= 1.0` filter — tried for both `lower` and `singular`
5. If nothing passes — return `[]` and the theme is skipped entirely

Removed `rel_spc`, `rel_gen`, and `ml` entirely. The "skip the theme" outcome is explicitly preferred over generating a semantically wrong spangram.

### Library Docs Consulted (Context7)
None — no third-party library touched, only native `fetch` and standard JS.

### Build & Test Results
```
$ node --check scripts/generate-strands.mjs
SYNTAX OK
```

### Open Issues
None.

## Developer Notes — fix ml-only word pollution in fetchWordsForSpangram

### Files Modified
- `scripts/generate-strands.mjs` — replaced `processResults(mlRes, 10000)` with new ml-as-amplifier logic

### Key Decisions
- ml results now only boost words already present in `scored` from a tight source (gen/com/trg/jjb). ml-only words never enter the pool at all.
- Added a fallback: if tight sources yield fewer than 15 words, ml words are admitted at score 1000 (with stricter freq >= 3.0) so the pool is never starved for sparse topics.
- Removed `countSignal(mlRes)` — ml is no longer a standalone signal source, so counting it would inflate the multi-source bonus for words that got their only real signal from ml.

### Library Docs Consulted (Context7)
none — pure JS logic change, no third-party library touched.

### Build & Test Results
`node --check scripts/generate-strands.mjs` — exit 0, no syntax errors.

### Open Issues
None. The fallback threshold (15 words) is a heuristic; tune it if certain themes still produce junk-filled puzzles.

## Developer Notes — expand word pool in fetchWordsForSpangram

### Files Modified
- `scripts/generate-strands.mjs` — replaced `fetchWordsForSpangram` body

### Key Decisions

**Multi-query loop instead of single singular query**
Old code fired all tight endpoints exactly once using `singular` (e.g. "peacock"). New code builds a `queries` array — `[singular, queryWord (if plural differs), spangram (if it differs from both)]` — and loops over each, accumulating results into `allResults.{gen,com,trg,jjb}`. This means topics like "deer" / spangram "reindeer" now get tight results for both words, and topics that are already singular still benefit from querying the spangram separately when it carries more semantic signal.

**Higher max values**
`rel_trg` raised from 80 → 100, `rel_gen` from 50 → 60, `rel_jjb` from 40 → 50, `rel_com` stays at 40 (changed to per-query so total scales with variants). This increases the raw candidate pool from each tight endpoint.

**ml fired once, after tight sources**
Previously ml was fired in the same parallel batch as tight sources. Now it fires sequentially after the tight loop, so the amplifier pass (`scored[word] += 10000`) operates on the already-populated `scored` map. The fallback path (threshold < 15) is unchanged in logic, only in order.

**Multi-source bonus updated to use allResults**
`countSignal` now counts against `allResults.gen/com/trg/jjb` (the accumulated arrays) rather than the per-query variables, so cross-query duplicates still register correctly.

### Library Docs Consulted (Context7)
None — no third-party library was touched; only Datamuse HTTP query parameters.

### Build & Test Results
```
node --check scripts/generate-strands.mjs
SYNTAX OK
```

### Open Issues
- The fallback threshold (15) is still in place. If a very obscure topic returns < 15 tight words even with multi-query, ml still activates. Consider lowering to 10 if junk persists.
- `singular` stripping is naïve (`replace(/s$/, '')`). "peacocks" → "peacock" ✓, but "bass" → "bas" ✗. Low-impact for now.
