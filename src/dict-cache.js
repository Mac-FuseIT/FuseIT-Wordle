/**
 * Dictionary validation using the Datamuse API.
 * 
 * Returns: { valid: boolean, error: string|null }
 * - valid=true, error=null: word confirmed in dictionary
 * - valid=false, error=null: word confirmed NOT in dictionary
 * - valid=false, error='api_error': API unreachable, can't determine
 */

/**
 * @param {string} word - lowercase word to validate
 * @param {object} db - D1 database binding (unused, kept for API compatibility)
 * @returns {Promise<{valid: boolean, error: string|null}>}
 */
export async function isValidWord(word, db) {
  const normalized = word.toLowerCase().trim();

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    const res = await fetch(
      `https://api.datamuse.com/words?sp=${encodeURIComponent(normalized)}&max=1&md=f`,
      { signal: controller.signal }
    );
    clearTimeout(timeout);

    if (!res.ok) {
      return { valid: false, error: 'api_error' };
    }

    const data = await res.json();
    // Word is valid only if the API returns an exact match AND has a minimum
    // frequency of 0.05 (per word-per-million). This rejects nonsense words
    // that Datamuse knows about (max nonsense freq seen: 0.019) while accepting
    // all real dictionary words (min real-word freq seen: 0.057).
    // See .workbench/word-validation/feedback-investigation.md for full analysis.
    const entry = data[0];
    const freqTag = entry && entry.tags ? entry.tags.find(t => t.startsWith('f:')) : null;
    const freq = freqTag ? parseFloat(freqTag.slice(2)) : 0;
    const valid = !!entry && entry.word === normalized && freq >= 0.05;

    return { valid, error: null };
  } catch (_) {
    // Timeout or network error
    return { valid: false, error: 'api_error' };
  }
}
