# Performance

## Caching Strategy (Upstash Redis)

### What's cached
- `/api/leaderboard` — 60 second TTL
- `/api/markets-signals` — 5 minute TTL
- `/api/research` — 2 minute TTL
- Vault stats — 60 second TTL

### Cache invalidation
Caches are invalidated on:
- Epoch settlement (keeper calls invalidate)
- New research submission
- New signal submitted

### Upstash setup
1. Create a free account at https://console.upstash.com
2. Create a new Redis database
3. Copy REST URL and token to `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` in `frontend/.env.local`
