# eblej24.com Postiz Fork - Maintainer Guide

This document describes the eblej24-specific customizations in this fork of [Postiz](https://github.com/gitroomhq/postiz-app). **AI assistants and maintainers MUST read this before making changes or merging from upstream.**

> **Important:** When making changes to this repository, UPDATE THIS FILE to document what was changed and why. Future maintainers need context.

---

## Table of Contents

1. [Repository Structure](#repository-structure)
2. [Protected Files](#-protected-files---do-not-overwrite)
3. [docker-compose.yaml Reference](#docker-composeyaml-reference)
4. [config/ Directory Reference](#config-directory-reference)
5. [data/ Directory Reference](#data-directory-reference)
6. [Making Changes](#making-changes)
7. [Merging from Upstream](#merging-from-upstream)
8. [Deployment](#deployment)
9. [Changelog](#changelog)

---

## Repository Structure

```
origin:   git@github.com:cohax-llc/eblej24-postiz.git  (our fork)
upstream: https://github.com/gitroomhq/postiz-app.git  (original)
```

### eblej24-Specific Files

```
postiz-app/
├── docker-compose.yaml          # ⚠️ PROTECTED - eblej24 infrastructure
├── .env.eblej24.example         # ⚠️ PROTECTED - Environment template
├── EBLEJ24_MAINTAINER.md        # ⚠️ PROTECTED - This file
├── config/                      # ⚠️ PROTECTED - Configuration files
│   ├── caddy/
│   │   └── Caddyfile            # Caddy reverse proxy rules
│   ├── postgres/
│   │   └── init-databases.sh    # Multi-database init script
│   └── temporal/
│       └── dynamicconfig/
│           └── development-sql.yaml
├── data/                        # ⚠️ PROTECTED - Persistent data (not in git)
│   ├── .gitignore
│   ├── postgres/
│   ├── redis/
│   └── postiz/
│       ├── config/
│       └── uploads/
└── [upstream files...]          # ✅ Safe to update from upstream
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

### If upstream modifies their `docker-compose.yaml`:
1. **Do NOT accept their changes**
2. Review their changes manually to see if new services/env vars are needed
3. Manually integrate any new requirements into our config
4. Document what you changed in the [Changelog](#changelog) section

---

## docker-compose.yaml Reference

Our `docker-compose.yaml` follows the [eblej24 Docker Compose Guide](https://github.com/cohax-llc/eblej24-server/blob/main/DOCKER_COMPOSE_GUIDE.md) and integrates with the eblej24 server infrastructure.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                 │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    eblej24_public network                        │
│  ┌─────────┐                                                     │
│  │  Caddy  │ ──── social.eblej24.com ────┐                      │
│  └─────────┘                              │                      │
│                                           ▼                      │
│                                    ┌───────────┐                 │
│                                    │  postiz   │                 │
│                                    │  :5000    │                 │
│                                    └─────┬─────┘                 │
└──────────────────────────────────────────┼──────────────────────┘
                                           │
┌──────────────────────────────────────────┼──────────────────────┐
│                    eblej24_internal network                      │
│                                           │                      │
│    ┌──────────────┬───────────────┬──────┴────────┐             │
│    ▼              ▼               ▼               ▼             │
│ ┌──────────┐ ┌─────────┐ ┌──────────┐ ┌─────────────────┐       │
│ │ postgres │ │  redis  │ │ temporal │ │   temporal-ui   │       │
│ │  :5432   │ │  :6379  │ │  :7233   │ │     :8080       │       │
│ └──────────┘ └─────────┘ └──────────┘ └─────────────────┘       │
│                                                                  │
│              Accessible via WireGuard VPN only                   │
└─────────────────────────────────────────────────────────────────┘
```

### Services Defined

| Service | Image | Networks | Purpose |
|---------|-------|----------|---------|
| `postiz` | `ghcr.io/gitroomhq/postiz-app:latest` | public, internal | Main application |
| `postgres` | `postgres:17-alpine` | internal | Shared database (postiz + temporal) |
| `postiz-redis` | `redis:7.2-alpine` | internal | Cache and session storage |
| `temporal` | `temporalio/auto-setup:1.28.1` | internal | Workflow engine |
| `temporal-ui` | `temporalio/ui:2.34.0` | internal | Temporal dashboard |
| `temporal-admin-tools` | `temporalio/admin-tools:1.28.1` | internal | CLI debugging tools |

### Networks

```yaml
networks:
  public:
    external: true
    name: eblej24_public    # Managed by eblej24-server

  internal:
    external: true
    name: eblej24_internal  # Managed by eblej24-server, no internet
```

**Important:** These networks are `external: true` because they are created by the main eblej24-server. This compose file joins existing networks, it does not create them.

### Environment Variables

#### Required (no defaults - will fail if missing):
```yaml
POSTIZ_JWT_SECRET      # JWT signing secret
POSTGRES_PASSWORD      # PostgreSQL password
POSTIZ_DATABASE_URL    # Full PostgreSQL connection string
```

#### Optional with defaults:
```yaml
POSTIZ_MAIN_URL        # Default: https://social.eblej24.com
POSTIZ_FRONTEND_URL    # Default: https://social.eblej24.com
POSTIZ_BACKEND_URL     # Default: https://social.eblej24.com/api
POSTGRES_USER          # Default: postgres
REDIS_PASSWORD         # Default: (empty, no auth)
REDIS_URL              # Default: redis://postiz-redis:6379
```

### Health Checks

All services have health checks for Caddy upstream monitoring and Docker restart:

| Service | Health Check |
|---------|-------------|
| postiz | `wget http://localhost:5000/` |
| postgres | `pg_isready -U postgres` |
| postiz-redis | `redis-cli ping` |
| temporal | `nc -z localhost 7233` |
| temporal-ui | `wget http://localhost:8080/` |

### Security Hardening

All services apply:
- `cap_drop: ALL` - Drop all Linux capabilities
- `restart: unless-stopped` - Auto-restart on failure
- No exposed ports - All traffic via Caddy or VPN
- Secrets via environment variables from `.env`

---

## config/ Directory Reference

### config/caddy/Caddyfile

Caddy reverse proxy configuration for `social.eblej24.com`.

```
social.eblej24.com {
    header { ... }           # Security headers
    handle /api/* { ... }    # API requests -> postiz:5000
    handle /uploads/* { ... } # File uploads (100MB limit)
    handle /socket.io/* { ... } # WebSocket support
    handle { ... }           # Frontend -> postiz:5000
}
```

**When to modify:**
- Adding new routes
- Changing upload size limits
- Adding rate limiting
- Updating security headers

### config/postgres/init-databases.sh

Creates multiple databases in a single PostgreSQL instance:

```bash
# Creates:
# - postiz (main application)
# - temporal (workflow engine)
# - temporal_visibility (temporal search)
```

**When to modify:**
- Adding new databases
- Changing database names
- Adding database extensions

### config/temporal/dynamicconfig/development-sql.yaml

Temporal workflow engine configuration:

```yaml
# Disables Elasticsearch (we don't use it)
# Sets history limits for PostgreSQL backend
```

**When to modify:**
- Adjusting Temporal performance settings
- Enabling/disabling Temporal features

---

## data/ Directory Reference

All persistent data is stored in `./data/` for easy backup.

```
data/
├── .gitignore              # Ignores all data, keeps structure
├── postgres/               # PostgreSQL data files
│   └── [PostgreSQL files]  # DO NOT MANUALLY EDIT
├── redis/                  # Redis persistence
│   └── [RDB/AOF files]     # DO NOT MANUALLY EDIT
└── postiz/
    ├── config/             # Application configuration
    └── uploads/            # User-uploaded files
```

### Backup

```bash
# Full backup
tar -czvf backup-$(date +%Y%m%d-%H%M%S).tar.gz ./data/

# Restore
docker compose down
rm -rf ./data/*
tar -xzvf backup-YYYYMMDD-HHMMSS.tar.gz
docker compose up -d
```

### Important Notes

- **Never commit data/ contents** - Contains user data and credentials
- **PostgreSQL data** - Stop postgres before backing up for consistency
- **Redis data** - AOF persistence enabled, safe for live backup
- **Uploads** - User files, can be large

---

## Making Changes

### Before Making Any Changes

1. **Read this entire document**
2. **Check if the file is protected** (see list above)
3. **Understand the eblej24 network architecture**

### Adding a New Service

1. Add service to `docker-compose.yaml` following the template:
   ```yaml
   newservice:
     image: vendor/image:tag
     container_name: newservice
     restart: unless-stopped
     environment:
       - CONFIG=${CONFIG_VAR}
     volumes:
       - ./data/newservice:/data
     networks:
       - internal  # or public, or both
     healthcheck:
       test: [...]
       interval: 30s
       timeout: 10s
       retries: 3
     cap_drop:
       - ALL
   ```

2. Create data directory: `mkdir -p ./data/newservice`

3. Add to `data/.gitignore`:
   ```
   !newservice/.gitkeep
   ```

4. If public, add Caddyfile entry in `config/caddy/Caddyfile`

5. Update `.env.eblej24.example` with new environment variables

6. **Update this file's [Changelog](#changelog)**

### Modifying docker-compose.yaml

1. **Check eblej24 guide** for conventions
2. **Keep external networks** - Never change to internal networks
3. **Use bind mounts to ./data/** for persistence
4. **Add health checks** for all services
5. **Apply security hardening** (cap_drop, no ports)
6. **Update this file's [Changelog](#changelog)**

### Adding Environment Variables

1. Add to `docker-compose.yaml` with default or required:
   ```yaml
   # With default
   MY_VAR: ${MY_VAR:-default_value}

   # Required (fails if missing)
   MY_VAR: ${MY_VAR:?MY_VAR is required}
   ```

2. Add to `.env.eblej24.example` with documentation:
   ```bash
   # Description of what this variable does
   MY_VAR=example_value
   ```

3. **Update this file's [Changelog](#changelog)**

---

## Merging from Upstream

### Standard Procedure

```bash
# 1. Fetch upstream changes
git fetch upstream

# 2. Check what's new
git log --oneline HEAD..upstream/main

# 3. Check commits ahead/behind
git rev-list --left-right --count HEAD...upstream/main
# Output: <ahead> <behind>

# 4. Merge (NOT rebase, to preserve history)
git merge upstream/main -m "Merge upstream/main: <summary of changes>"

# 5. If conflicts in protected files, ALWAYS keep ours:
git checkout --ours docker-compose.yaml
git checkout --ours .env.eblej24.example
git checkout --ours config/caddy/Caddyfile
git checkout --ours config/postgres/init-databases.sh
git checkout --ours config/temporal/dynamicconfig/development-sql.yaml
git checkout --ours EBLEJ24_MAINTAINER.md
git add <conflicted-files>
git merge --continue

# 6. Push to origin
git push origin main
```

### After Merging

- [ ] Verify `docker-compose.yaml` still has eblej24 networks
- [ ] Check if upstream added new environment variables (review their docker-compose)
- [ ] Check if upstream added new services that we need
- [ ] Review Prisma schema changes for database compatibility
- [ ] **Update [Changelog](#changelog) with merge details**

### If Upstream Adds New Requirements

If upstream's docker-compose shows new services or env vars we need:

1. **Do NOT copy their docker-compose** - It won't work with eblej24
2. Manually add the new service following our conventions
3. Update `.env.eblej24.example`
4. Update this documentation
5. Document in [Changelog](#changelog)

---

## Deployment

### Prerequisites

1. eblej24-server must be running (creates networks)
2. DNS configured: `social.eblej24.com` → server IP
3. Caddyfile imported on main server

### First-Time Setup

```bash
# 1. Clone repository
git clone git@github.com:cohax-llc/eblej24-postiz.git
cd eblej24-postiz

# 2. Create environment file
cp .env.eblej24.example .env

# 3. Generate secure secrets
openssl rand -base64 32  # For POSTIZ_JWT_SECRET
openssl rand -base64 24  # For POSTGRES_PASSWORD
openssl rand -base64 24  # For REDIS_PASSWORD

# 4. Edit .env with your values
vim .env

# 5. Start services
docker compose up -d

# 6. Check logs
docker compose logs -f

# 7. Import Caddyfile to main server (via CaddyManager or CLI)
```

### Updating

```bash
# Pull latest changes
git pull origin main

# Restart services (if docker-compose changed)
docker compose up -d

# Or just restart specific service
docker compose restart postiz
```

### Troubleshooting

```bash
# Check service status
docker compose ps

# View logs
docker compose logs postiz
docker compose logs postgres

# Check network connectivity
docker network inspect eblej24_public
docker network inspect eblej24_internal

# Enter container for debugging
docker exec -it postiz sh
docker exec -it postgres psql -U postgres
```

---

## Changelog

**Maintainers: Add entries here when making changes. Most recent first.**

### 2026-01-23 - Initial eblej24 Integration

**Author:** Claude Opus 4.5 (AI Assistant)

**Changes:**
- Created `docker-compose.yaml` with eblej24 network integration
- Created `.env.eblej24.example` with all environment variables
- Created `config/caddy/Caddyfile` for social.eblej24.com routing
- Created `config/postgres/init-databases.sh` for multi-database setup
- Created `config/temporal/dynamicconfig/development-sql.yaml`
- Created `data/` directory structure with `.gitignore`
- Created `EBLEJ24_MAINTAINER.md` (this file)

**Architecture Decisions:**
- Single PostgreSQL instance with multiple databases (postiz, temporal, temporal_visibility)
- Redis with optional password authentication
- Temporal without Elasticsearch (uses PostgreSQL for visibility)
- All persistent data in `./data/` for easy backup
- No exposed ports - all traffic via Caddy reverse proxy
- Security hardening with `cap_drop: ALL`

**Removed from upstream docker-compose:**
- `temporal-elasticsearch` - Not needed, using PostgreSQL visibility
- `spotlight` - Development debugging tool
- Separate `temporal-postgresql` - Consolidated into single postgres

---

## Contact

- **eblej24 Infrastructure:** Contact eblej24 server administrator
- **Postiz Application:** https://github.com/gitroomhq/postiz-app
- **This Repository:** https://github.com/cohax-llc/eblej24-postiz
