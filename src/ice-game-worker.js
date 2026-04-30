// Worker entry point for Durable Object
export { IceGameSession } from './ice-game-session.js';

export default {
  async fetch(request, env) {
    return new Response('Ice.IT Worker - Use via Pages binding', { status: 200 });
  }
};
