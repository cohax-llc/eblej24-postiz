# eblej24: Fix browser requesting :5000 (config only)

Your `.env` is correct (no :5000). If the browser still requests `https://social.eblej24.com:5000/api/`, the pre-built image has that URL baked into the client bundle at build time. Fix with **config only**: build your own image with build-args, and/or have Caddy handle port 5000.

---

## Option 1: Build your own image with the correct URL (recommended)

Next.js bakes `NEXT_PUBLIC_*` at **build time**. Build the image with the correct URLs so the client bundle uses them.

### 1. Build-args in Dockerfile.dev

Ensure `Dockerfile.dev` accepts and uses build-args (e.g. `ARG NEXT_PUBLIC_BACKEND_URL` and `ENV NEXT_PUBLIC_BACKEND_URL=...` before `pnpm run build`). If the repo already has that, skip to the build step.

### 2. Build the image

From the repo root:

```bash
docker build -f Dockerfile.dev \
  --build-arg NEXT_PUBLIC_BACKEND_URL=https://social.eblej24.com/api \
  --build-arg FRONTEND_URL=https://social.eblej24.com \
  -t your-registry/postiz-app:eblej24 .
```

Use the same values as in your `.env` (no :5000).

### 3. Run your image instead of the pre-built one

In `docker-compose.yaml` (or wherever you run Postiz), use `image: your-registry/postiz-app:eblej24` instead of `ghcr.io/gitroomhq/postiz-app:v2.12.1`. Keep the same `environment:` and `.env` so runtime env stays correct.

---

## Option 2: Caddy handles port 5000 (no rebuild)

If you cannot rebuild, expose port 5000 and let Caddy proxy to the app so `https://social.eblej24.com:5000/...` works.

- Your host must route **port 5000** to the Caddy container (not to the Postiz app).
- In Caddy, add a **server** that listens on `:5000` for `social.eblej24.com` and does `reverse_proxy` to `eb24-postiz-app:5000` (same upstream as :443). Enable TLS for that host on port 5000 (same certificate as :443 is fine).

Then when the browser requests `https://social.eblej24.com:5000/api/`, Caddy proxies the request to the app and the app responds.

**Caddy JSON idea** (merge into your existing config as needed):

- In `apps.http.servers`, add (or extend) a server that has `"listen": [":5000"]` and a route matching `host` `social.eblej24.com` with a `reverse_proxy` handle to `eb24-postiz-app:5000`.
- Ensure TLS is configured for `social.eblej24.com` on that listener (e.g. same automation as for :443).

**Note:** Prefer Option 1 so the client uses the canonical URL (no :5000). Option 2 is a workaround when you cannot rebuild.
