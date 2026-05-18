export async function onRequestGet({ params, request, env }) {
  const sessionId = params.sessionId;
  const id = env.CHESS_GAME.idFromName(sessionId);
  const stub = env.CHESS_GAME.get(id);
  return stub.fetch(request);
}
