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
      `https://api.datamuse.com/words?sp=${encodeURIComponent(normalized)}&max=1`,
      { signal: controller.signal }
    );
    clearTimeout(timeout);

    if (!res.ok) {
      return { valid: false, error: 'api_error' };
    }

    const data = await res.json();
    // Word is valid only if the API returns it as an exact match
    const valid = data.length > 0 && data[0].word === normalized;

    return { valid, error: null };
  } catch (_) {
    // Timeout or network error
    return { valid: false, error: 'api_error' };
  }
}
