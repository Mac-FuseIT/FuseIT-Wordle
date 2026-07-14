export async function onRequestGet({ request, env }) {
  const id = env.ROULETTE_TABLE.idFromName('roulette-main');
  const stub = env.ROULETTE_TABLE.get(id);
  return stub.fetch(request);
}
