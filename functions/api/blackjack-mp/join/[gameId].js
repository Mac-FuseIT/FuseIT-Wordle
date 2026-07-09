export async function onRequestGet({ params, request, env }) {
  const gameId = params.gameId;
  const id = env.BLACKJACK_GAME.idFromName(gameId);
  const stub = env.BLACKJACK_GAME.get(id);
  return stub.fetch(request);
}
