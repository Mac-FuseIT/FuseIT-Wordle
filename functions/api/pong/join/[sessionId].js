export async function onRequestGet({ params, request, env }) {
  const sessionId = params.sessionId;
  const id = env.PONG_GAME.idFromString(sessionId);
  const stub = env.PONG_GAME.get(id);
  return stub.fetch(request);
}
