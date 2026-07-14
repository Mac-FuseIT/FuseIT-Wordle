import { jsonResponse, errorResponse, requireAuth } from '../../../src/db.js';

export async function onRequestGet({ request, env }) {
  const auth = await requireAuth(request, env);
  if (!auth) return errorResponse('Unauthorized', 401);

  try {
    const id = env.ROULETTE_TABLE.idFromName('roulette-main');
    const stub = env.ROULETTE_TABLE.get(id);
    const res = await stub.fetch(new Request('https://internal/status'));
    const data = await res.json();
    return jsonResponse(data);
  } catch (e) {
    return jsonResponse({ players: [], phase: 'idle', roundNumber: 0 });
  }
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}
