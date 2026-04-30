export async function onRequest({ params, env, request }) {
  const sessionId = params.sessionId;
  const upgradeHeader = request.headers.get('Upgrade');
  
  if (upgradeHeader !== 'websocket') {
    return new Response('Expected WebSocket', { status: 426 });
  }

  const id = env.ICE_GAME.idFromName(sessionId);
  const stub = env.ICE_GAME.get(id);
  
  // Forward the WebSocket upgrade request to the Durable Object
  return stub.fetch(request.url.replace(request.url, 'https://fake/websocket'), request);
}
