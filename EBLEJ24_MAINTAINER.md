# eblej24.com Postiz Fork - Maintainer Guide

This document describes the eblej24-specific customizations in this fork of [Postiz](https://github.com/gitroomhq/postiz-app). **AI assistants and maintainers must read this before making changes or merging from upstream.**

---

## Repository Structure

```
origin:   git@github.com:cohax-llc/eblej24-postiz.git  (our fork)
upstream: https://github.com/gitroomhq/postiz-app.git  (original)
```

---

## ⚠️ PROTECTED FILES - DO NOT OVERWRITE

These files contain eblej24-specific infrastructure configuration. **Never accept upstream changes to these files** during merges:

| File | Purpose |
|------|---------|
| `docker-compose.yaml` | eblej24 infrastructure integration |
| `.env.eblej24.example` | Environment template for eblej24 |
| `config/caddy/Caddyfile` | Caddy reverse proxy config |
| `config/postgres/init-databases.sh` | Multi-database init script |
| `config/temporal/dynamicconfig/development-sql.yaml` | Temporal config |
| `data/` | Persistent data directory structure |
| `data/.gitignore` | Data directory gitignore |
| `EBLEJ24_MAINTAINER.md` | This file |

### If upstream modifies `docker-compose.yaml`:
- **Do NOT accept their changes**
- Review their changes manually to see if new services/env vars are needed
- Manually integrate any new requirements into our config
- Our config uses eblej24 networks, not their default setup

---

## ✅ SAFE TO UPDATE FROM UPSTREAM

All other files can be safely updated from upstream, including:
- `apps/` - Application code
- `libraries/` - Shared libraries
- `packages/` - Package configs
- `prisma/` - Database schema (review carefully)
- `*.json` - Package configs
- `*.md` - Documentation (except this file)

---

## Merging from Upstream

### Standard merge procedure:

```bash
# 1. Fetch upstream changes
git fetch upstream

# 2. Check what's new
git log --oneline HEAD..upstream/main

# 3. Merge (NOT rebase, to preserve history)
git merge upstream/main -m "Merge upstream/main: <summary of changes>"

# 4. If conflicts in protected files, ALWAYS keep ours:
git checkout --ours docker-compose.yaml
git checkout --ours .env.eblej24.example
git checkout --ours config/caddy/Caddyfile
git checkout --ours config/postgres/init-databases.sh
git checkout --ours config/temporal/dynamicconfig/development-sql.yaml
git add <conflicted-files>
git merge --continue

# 5. Push to origin
git push origin main
```

### After merging, verify:
- [ ] `docker-compose.yaml` still has eblej24 networks
- [ ] No new required environment variables were added upstream (check their docker-compose)
- [ ] Prisma schema changes don't break our database setup

---

## eblej24 Infrastructure Overview

### Networks (external, managed by eblej24-server)
- `eblej24_public` - Internet-facing services via Caddy
- `eblej24_internal` - Private services, VPN access only

### Services
| Service | Network | Port | Description |
|---------|---------|------|-------------|
| `postiz` | public + internal | 5000 | Main app (social.eblej24.com) |
| `postgres` | internal | 5432 | Shared PostgreSQL |
| `postiz-redis` | internal | 6379 | Redis cache |
| `temporal` | internal | 7233 | Workflow engine |
| `temporal-ui` | internal | 8080 | Temporal dashboard (VPN) |

### Data Storage
All persistent data in `./data/` for easy backup:
```
./data/
├── postgres/           # PostgreSQL data
├── redis/              # Redis persistence
└── postiz/
    ├── config/         # App configuration
    └── uploads/        # User uploads
```

---

## Required Environment Variables

These MUST be set in `.env` (no defaults for security):

```bash
POSTIZ_JWT_SECRET=<generate: openssl rand -base64 32>
POSTGRES_PASSWORD=<secure password>
POSTIZ_DATABASE_URL=postgresql://postgres:<password>@postgres:5432/postiz
```

Optional but recommended:
```bash
REDIS_PASSWORD=<secure password>
REDIS_URL=redis://:<password>@postiz-redis:6379
```

---

## Deployment

```bash
# Prerequisites: eblej24-server must be running (creates networks)

# 1. Configure environment
cp .env.eblej24.example .env
# Edit .env with secure values

# 2. Start services
docker compose up -d

# 3. Import Caddyfile to main eblej24 server
# (via CaddyManager or append to main Caddyfile)
```

---

## Contact

For eblej24 infrastructure questions, contact the eblej24 server administrator.

For Postiz application issues, see upstream: https://github.com/gitroomhq/postiz-app
