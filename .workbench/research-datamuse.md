# Research: Datamuse API — Tight Semantic Relationships for Spangram Selection

## Summary

The Datamuse API offers 13 distinct relationship types. For spangram selection, the problem is that `ml` (means-like) uses a reverse-dictionary + word2vec model that traverses loose semantic chains (fear-of-spiders → chicken), and `rel_trg` adds corpus co-occurrence which is noisy. The solution is a **multi-signal intersection approach**: run several structurally distinct queries, score words by how many signals they appear in, and optionally validate by checking the reverse relationship. The `topics` parameter is a ranking hint only (not a filter), but used alongside tight lexical relations it significantly improves signal quality.

## Sources

| Source | Type | Date | Link |
|--------|------|------|------|
| Datamuse API official docs | Official Docs | 2016-12-05 (v1.1, ongoing) | https://www.datamuse.com/api/ |
| Datamuse data sources section | Official Docs | same | https://www.datamuse.com/api/#data-sources |
| Datamuse API docs on apis.io | Community summary | N/A | https://apis.io/apis/datamuse/datamuse-api/ |

---

## Findings

### 1. Which endpoints give the TIGHTEST semantic relationship?

Ranking from tightest to loosest for a topic like "spiders":

| Endpoint | Tightness | Notes |
|----------|-----------|-------|
| `rel_syn` | 🔒 Very tight | WordNet synset — exact synonym only. Small result set. `spider` → `arachnid` |
| `rel_spc` | 🔒 Very tight | Direct hypernym (category): `spider` → `arachnid`, `arthropod` |
| `rel_gen` | 🔒 Tight | Direct hyponyms: `spider` → `tarantula`, `cobweb spider`, `wolf spider` |
| `rel_com` | 🔒 Tight | Comprises (parts): `spider` → `fang`, `silk`, `web` |
| `rel_jjb` | 🟡 Medium-tight | Common adjectives: `spider` → `venomous`, `hairy`, `spinning`, `poisonous` |
| `rel_trg` | 🟡 Medium | Co-occurrence triggers: `spider` → `web`, `bite`, `silk`, `trap` — mostly on-topic but noisy at edges |
| `rel_jja` | 🟡 Medium | (only useful if topic is an adjective, not applicable for nouns like "spiders") |
| `ml` | 🔴 Loose | Reverse dictionary + word2vec paraphrase: crosses phobia, metaphor, fear domains → "chicken", "monster" |
| `rel_bga` / `rel_bgb` | 🔴 Loose | Bigram followers/predecessors: language collocations, not semantic |

**Key insight from the docs:** `rel_syn`, `rel_spc`, `rel_gen`, `rel_com`, `rel_par` are all backed by **WordNet 3.0** — a structured lexical ontology. These give the most reliable domain-bounded results. `ml` uses word2vec + Paraphrase Database (PPDB "XXL"), which is known to follow metaphorical and associative chains far beyond the intended domain.

### 2. Concrete API URLs for "spiders"

```
# Synonyms (WordNet) — very tight
https://api.datamuse.com/words?rel_syn=spider&max=20&md=f
# Expected: arachnid, and a few others

# Hypernyms (kind of) — tight category
https://api.datamuse.com/words?rel_spc=spider&max=20&md=f
# Expected: arachnid, arthropod, invertebrate

# Hyponyms (types of) — concrete instances
https://api.datamuse.com/words?rel_gen=spider&max=20&md=f
# Expected: tarantula, black widow, orb weaver, cobweb spider, wolf spider

# Comprises (parts of a spider)
https://api.datamuse.com/words?rel_com=spider&max=20&md=f
# Expected: web, silk, fang, venom, spinneret

# Adjectives describing spider (corpus-based, tight to biology/behavior)
https://api.datamuse.com/words?rel_jjb=spider&max=30&md=f
# Expected: venomous, poisonous, hairy, spinning, giant, common, deadly

# Triggers (co-occurrence) with topics hint to constrain reranking
https://api.datamuse.com/words?rel_trg=spider&topics=arachnid&max=50&md=f
# Expected: web, silk, bite, trap, venom (reranked away from fear/phobia words)

# Current approach — too broad
https://api.datamuse.com/words?ml=spiders&max=150&md=f
# Returns: arachnid, tarantula BUT ALSO chicken, monster, nightmare (via phobia/fear chains)
```

### 3. Should we use the `topics` parameter?

**Yes, but understand its limitation.** From the official docs:

> "Topics can be thought of as context hints. The latter only impact the **order** in which results are returned."

`topics` does NOT filter results — it re-ranks them. So `ml=spiders&topics=arachnid` will still return "chicken", but "chicken" will rank lower. Combined with a `max` cutoff on a tighter query like `rel_trg`, it's genuinely useful.

**Best use**: Add `topics=<topic>` to `rel_trg` and `rel_jjb` queries to push domain-relevant words to the top. Use `max=30` instead of `max=150` so only the best-ranked results are kept.

Example:
```
https://api.datamuse.com/words?rel_trg=spider&topics=spider&max=30&md=f
```

### 4. Multi-query intersection approach

This is the highest-value technique. The rationale: a word that appears in results from structurally different queries (WordNet ontology + corpus co-occurrence + descriptive adjective path) is almost certainly genuinely in the topic domain.

**Proposed scoring formula:**

```js
async function fetchTightSpangramCandidates(topic) {
  const [synRes, spcRes, genRes, comRes, jjbRes, trgRes] = await Promise.all([
    fetch(`https://api.datamuse.com/words?rel_syn=${topic}&max=50&md=f`).then(r=>r.json()).catch(()=>[]),
    fetch(`https://api.datamuse.com/words?rel_spc=${topic}&max=30&md=f`).then(r=>r.json()).catch(()=>[]),
    fetch(`https://api.datamuse.com/words?rel_gen=${topic}&max=50&md=f`).then(r=>r.json()).catch(()=>[]),
    fetch(`https://api.datamuse.com/words?rel_com=${topic}&max=30&md=f`).then(r=>r.json()).catch(()=>[]),
    fetch(`https://api.datamuse.com/words?rel_jjb=${topic}&max=40&md=f&topics=${topic}`).then(r=>r.json()).catch(()=>[]),
    fetch(`https://api.datamuse.com/words?rel_trg=${topic}&max=40&md=f&topics=${topic}`).then(r=>r.json()).catch(()=>[]),
  ]);

  const scores = {};

  // WordNet-backed relations get high weight — very reliable
  for (const w of synRes) addScore(scores, w, 1000);
  for (const w of spcRes) addScore(scores, w, 800);  // hypernym: "arachnid"
  for (const w of genRes) addScore(scores, w, 800);  // hyponym: "tarantula"
  for (const w of comRes) addScore(scores, w, 600);  // parts: "web", "venom"
  
  // Corpus-backed relations get lower weight
  for (const w of jjbRes) addScore(scores, w, 400);  // "venomous", "spinning"
  for (const w of trgRes) addScore(scores, w, 300);  // "web", "bite"

  // Filter and rank
  return Object.entries(scores)
    .filter(([word]) => {
      // length check for spangram (6-8 letters)
      if (!/^[a-z]+$/.test(word) || word.length < 6 || word.length > 8) return false;
      // frequency check — must be a known common word
      const freq = getFreq(word); // from md=f tag
      return freq >= 2.0;
    })
    .sort((a, b) => b[1] - a[1])
    .map(([word]) => word);
}
```

Key insight: **a word appearing in 2+ of the WordNet-backed relations (`syn`, `spc`, `gen`, `com`) is almost guaranteed to be domain-correct**.

### 5. Scoring adjustments

Current script uses a flat 50,000 boost for `rel_trg`. Proposed improvements:

1. **Differentiated weights by signal source** — WordNet signals (syn, spc, gen, com) should outweigh corpus signals (trg, jjb) because they are ontologically grounded, not statistically noisy.

2. **Frequency band filtering** — Keep the `freq >= 2.0` filter but also add an **upper** bound: `freq < 200`. Words like "the", "is", "very" will have huge frequency. This prevents stop-word-like words ranking too high from `rel_jjb`.

3. **Signal count bonus** — Any word appearing in 3+ distinct signal sources gets a large multiplier (e.g. ×5). This is the intersection strategy made concrete.

4. **Single-word filter** — Multi-word results like "black widow" or "wolf spider" are valid semantically but useless as single-word spangrams. Filter with `/^[a-z]+$/`.

### 6. Validation step (reverse-check)

**Yes — this is highly effective.** The idea: after picking a spangram candidate, check if the original topic appears in the results of querying with that candidate.

```js
async function isReverseCohesive(candidate, topic) {
  // Does querying candidate's neighbors return the topic?
  const res = await fetch(
    `https://api.datamuse.com/words?ml=${candidate}&max=50`
  ).then(r => r.json()).catch(() => []);
  return res.some(w => w.word === topic || w.word === topic.replace(/s$/, ''));
}
```

If `spangram=arachnid` and `topic=spiders`, then `ml=arachnid` should return "spider" or "spiders" near the top. If it doesn't, the candidate is likely off-domain.

This validation adds ~1 API call per candidate but can be run only on the top 3-5 candidates after scoring.

**Warning:** Do not validate using `ml` alone — the "chicken" problem goes both ways. Better: check if the topic appears in `rel_gen` or `rel_syn` results for the candidate. If `rel_gen=arachnid` includes "spider", that's extremely strong confirmation.

---

## Conflicts or Uncertainties

- **`rel_trg` quality is topic-dependent.** For concrete nouns like "spider" or "ocean", it works well. For abstract topics it can drift badly.
- **`rel_jjb` returns adjectives, not nouns.** For spangram selection (which needs nouns/verbs like "tarantula", "spinning"), `rel_jjb` words are useful as fill-word candidates but rarely qualify as spangrams by length/type.
- **WordNet coverage gaps.** Unusual or technical terms may not appear in WordNet, so `rel_syn`/`rel_spc`/`rel_gen`/`rel_com` can return empty sets for niche topics. Always fall back to `rel_trg` + frequency filter.
- **API rate note.** Starting January 1, 2027, Datamuse will require an API key and limit to 100,000 requests/day. The multi-query approach (6 calls per candidate lookup) will consume more quota — not a current problem for a script run periodically, but worth noting.

---

## Recommendation

**Replace the current two-query approach (`ml` + `rel_trg`) with the following three-tier strategy:**

**Tier 1 — Structural signals (run first, small max):**
```
rel_syn=<topic>&max=30&md=f
rel_spc=<topic>&max=30&md=f   ← hypernyms: category of topic
rel_gen=<topic>&max=50&md=f   ← hyponyms: specific types OF topic  ← best for spangrams
rel_com=<topic>&max=30&md=f   ← parts of topic
```

**Tier 2 — Corpus signals (run in parallel, with topics hint):**
```
rel_jjb=<topic>&max=30&md=f&topics=<topic>
rel_trg=<topic>&max=40&md=f&topics=<topic>
```

**Tier 3 — Score and intersect:**
- WordNet signals: 800–1000 points each
- Corpus signals: 300–400 points each
- Minimum qualifying score: at least 1 point (appeared in at least one query)
- Bonus: multiply score by 3 for any word appearing in 2+ sources

**Tier 4 — Validate top candidates:**
- Check `rel_gen=<candidate>` to see if topic appears among the results
- Alternatively: check `rel_spc=<candidate>` or `rel_syn=<candidate>` for topic

**Drop `ml=<topic>` entirely for spangram selection.** It is the source of the "chicken" problem. Use `ml` only for fill-word generation (where a broader pool is acceptable), and even then apply the `topics` hint and a tighter `max`.

**Example for topic "spiders":**
- `rel_gen=spider` → "tarantula" ✅, "black widow" (multi-word, filtered out)
- `rel_syn=spider` → "arachnid" ✅  
- `rel_jjb=spider&topics=spider` → "venomous" (adj — valid fill word, too short for spangram)
- `rel_trg=spider&topics=spider` → "cobweb" ✅ (6 letters, fits!)

Result pool: "tarantula" (9 letters, too long for 6-8 filter), "arachnid" (8 letters ✅), "cobweb" (but only 6 letters, likely qualifies), "venom" (5 letters — fill word only), "spinning" (8 letters ✅ via jjb)
