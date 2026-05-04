import { PongGameSession } from './pong-game-session.js';

export { PongGameSession };
export default {
  fetch() {
    return new Response('Worker for Durable Objects only', { status: 200 });
  }
};
