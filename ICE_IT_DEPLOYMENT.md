# Ice.IT Deployment Guide

## Overview
Ice.IT is now deployed with the following components:
- ✅ Frontend (Flutter web)
- ✅ API endpoints (Cloudflare Pages Functions)
- ✅ Database tables (D1)
- ⚠️ Durable Objects (requires manual setup)

## Completed Steps

### 1. Database Migration
```bash
npx wrangler d1 execute fuseit-wordle-db --file=migrations/0003_ice.sql --remote
```
✅ Tables created: `ice_sessions`, `ice_matches`

### 2. Frontend Build & Deploy
```bash
cd frontend && flutter build web --release
npx wrangler pages deploy frontend/build/web
```
✅ Deployed to: https://fuseit-wordle.pages.dev

## Manual Setup Required: Durable Objects

Cloudflare Pages requires Durable Objects to be configured via the dashboard (not wrangler.toml).

### Steps:

1. **Go to Cloudflare Dashboard**
   - Navigate to Workers & Pages → fuseit-wordle

2. **Settings → Functions → Durable Object Bindings**
   - Click "Add Binding"
   - Variable name: `ICE_GAME`
   - Durable Object class: `IceGameSession`
   - Durable Object namespace: Create new namespace "ice-game-sessions"

3. **Deploy the Durable Object Class**
   
   The class is exported in `/functions/_worker.js`:
   ```javascript
   export { IceGameSession } from '../src/ice-game-session.js';
   ```

   Cloudflare Pages automatically picks this up from the Functions directory.

4. **Verify Binding**
   - After saving, redeploy the Pages project
   - The binding will be available as `env.ICE_GAME` in API functions

### Alternative: Deploy as Separate Worker (Advanced)

If the above doesn't work, deploy the Durable Object as a standalone Worker:

```bash
# Create worker with Durable Object
npx wrangler deploy src/ice-game-session.js --name fuseit-wordle-worker

# Then bind it in Pages dashboard:
# - Variable name: ICE_GAME
# - Service: fuseit-wordle-worker
# - Class: IceGameSession
```

## Testing Ice.IT

Once Durable Objects are configured:

1. Visit https://fuseit-wordle.pages.dev
2. Click "Ice.IT" from the main menu
3. Create a new session with custom settings
4. Open in another browser/tab and join the session
5. Play live hockey!

## API Endpoints

- `POST /api/ice/create` - Create new game session
- `GET /api/ice/sessions` - List open sessions
- `GET /api/ice/join/[sessionId]` - WebSocket upgrade for gameplay

## Game Features

- **Real-time multiplayer**: WebSocket connections via Durable Objects
- **Configurable settings**: Best of 3/5/8/12/15/18/25, puck speed (Slow/Normal/Fast/Turbo), players per side (1/2/3)
- **Server-authoritative physics**: 60 FPS game loop with collision detection
- **Mobile-friendly**: Touch controls for paddle movement

## Troubleshooting

### "Failed to create session"
- Check Durable Object binding is configured
- Verify `ICE_GAME` binding exists in Pages settings

### WebSocket connection fails
- Ensure Durable Object namespace is created
- Check browser console for connection errors
- Verify `/api/ice/join/[sessionId]` endpoint returns 101 Switching Protocols

### Game doesn't start
- Need exactly 2 players (one per team)
- Check both players successfully connected via WebSocket
- Look for "game_start" message in browser console

## Architecture

```
┌─────────────┐
│   Flutter   │ ← User Interface
│   Frontend  │
└──────┬──────┘
       │ HTTP/WebSocket
┌──────▼──────────────────┐
│  Cloudflare Pages       │
│  ┌──────────────────┐   │
│  │ API Functions    │   │ ← /api/ice/*
│  └────┬─────────────┘   │
│       │                 │
│  ┌────▼─────────────┐   │
│  │ Durable Objects  │   │ ← IceGameSession
│  │ (Game Sessions)  │   │    60 FPS game loop
│  └──────────────────┘   │
│       │                 │
│  ┌────▼─────────────┐   │
│  │ D1 Database      │   │ ← ice_sessions, ice_matches
│  └──────────────────┘   │
└─────────────────────────┘
```

## Next Steps

1. ✅ Complete manual Durable Object setup
2. Test end-to-end gameplay
3. Monitor WebSocket connection stability
4. Optimize physics (if needed)
5. Add reconnection logic for dropped connections
6. Implement match history storage
7. Add spectator mode (future)


# 1. Deploy the Worker with Durable Object
npx wrangler deploy --config wrangler-worker.toml

# 2. Go to Cloudflare Dashboard → Workers & Pages → fuseit-wordle (your Pages project)
# 3. Settings → Bindings → Add binding
# 4. Choose "Service binding"
#    - Variable name: ICE_GAME
#    - Service: fuseit-wordle-worker
#    - Environment: production
# 5. Save and redeploy your Pages project