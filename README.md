# WordIT

A daily word game deployed on Cloudflare's free tier. Each day a new word is selected with a varying length (4–8 letters). Guess the word with color-coded feedback — green, yellow, grey.

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (for building the frontend)
- [Node.js](https://nodejs.org/) (for wrangler CLI)
- A [Cloudflare account](https://dash.cloudflare.com/sign-up) (free tier works)

## Setup

### 1. Install wrangler

```bash
npm install
```

### 2. Log in to Cloudflare

```bash
npx wrangler login
```

This opens a browser window — authorize wrangler to access your Cloudflare account.

### 3. Create the D1 database

```bash
npx wrangler d1 create fuseit-word-db
```

This outputs something like:

```
✅ Successfully created DB 'fuseit-word-db'
database_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

Copy the `database_id` and paste it into `wrangler.toml`, replacing `YOUR_D1_DATABASE_ID`:

```toml
[[d1_databases]]
binding = "DB"
database_name = "fuseit-word-db"
database_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # ← paste here
```

### 4. Run the database migration

```bash
npx wrangler d1 execute fuseit-word-db --file=migrations/0001_init.sql --remote
```

When prompted, confirm you want to run against the **remote** database.

### 5. Build the Flutter frontend

```bash
cd frontend
flutter build web --release
cd ..
```

The compiled output goes to `frontend/build/web/`.

### 6. Deploy to Cloudflare Pages

```bash
npx wrangler pages deploy frontend/build/web
```

On first deploy, wrangler will ask you to create a new project — name it `fuseit-word` (or whatever you like). It will give you a URL like `https://fuseit-word.pages.dev`.

### 7. Bind D1 to your Pages project

Go to the [Cloudflare dashboard](https://dash.cloudflare.com/):

1. Navigate to **Workers & Pages** → your project (`fuseit-word`)
2. Go to **Settings** → **Bindings**
3. Click **Add** → **D1 Database**
4. Set variable name to `DB` and select `fuseit-word-db`
5. Save, then **redeploy** (or push a new deploy):

```bash
npx wrangler pages deploy frontend/build/web
```

Your site is now live.

## Local Development

To run everything locally:

```bash
# Build frontend first
cd frontend && flutter build web --release && cd ..

# Start local dev server with D1
npx wrangler pages dev frontend/build/web --d1=DB=fuseit-word-db
```

This starts a local server (usually `http://localhost:8788`) with a local D1 database. Run the migration against local D1 first:

```bash
npx wrangler d1 execute fuseit-word-db --file=migrations/0001_init.sql --local
```

## Project Structure

```
├── frontend/              Flutter web app
│   └── lib/
│       ├── main.dart              App entry point
│       ├── screens/               Login, Game, Leaderboard screens
│       ├── widgets/               TileGrid, Keyboard, LeaderboardTable
│       ├── services/              API HTTP client
│       └── models/                Data classes
├── functions/api/         Cloudflare Pages Functions (API)
│   ├── login.js           POST /api/login
│   ├── today.js           GET  /api/today
│   ├── guess.js           GET|POST /api/guess
│   └── leaderboard.js     GET  /api/leaderboard
├── src/                   Shared backend logic
│   ├── words.js           Word lists (4–8 letters)
│   ├── word-selection.js  Deterministic daily word picker
│   └── db.js              Response helpers
├── migrations/
│   └── 0001_init.sql      Database schema
├── wrangler.toml          Cloudflare config
└── package.json
```

## Redeploying After Changes

```bash
cd frontend && flutter build web --release && cd ..
npx wrangler pages deploy frontend/build/web
```

Or connect your Git repo to Cloudflare Pages for automatic deploys on push. Set the build command to `cd frontend && flutter build web --release` and the output directory to `frontend/build/web`.

4-letter: 603 words
5-letter: 756 words
6-letter: 613 words
7-letter: 623 words
8-letter: 870 words

