# 502 Bad Gateway on Signup – Problem State (eblej24 / social.eblej24.com)

**Date:** 2026-02-02  
**Environment:** External (not local). Caddy + Docker Compose; app at https://social.eblej24.com  
**Purpose:** Context file for debugging. Update this as we narrow the cause and apply fixes.

---

## 1. Symptom

- **Error:** HTTP 502 Bad Gateway (Cloudflare in front).
- **When:** During **new user signup** (Create Account on the register page).
- **Observed:** “The web server reported a bad gateway error” (Cloudflare).
- **What works:** https://social.eblej24.com/ loads; only the signup flow returns 502.

So: **502 occurs specifically when creating a new user**, not on normal page load or (presumably) login.

---

## 2. Request Path

1. **User:** Submits signup form (email/password/company, or OAuth then complete profile).
2. **Frontend:** `POST` to `/auth/register` (e.g. `fetchData('/auth/register', { method: 'POST', body: JSON.stringify(data) })`).
3. **Caddy:** For `social.eblej24.com`, routes `/api/*` to **`eb24-postiz-app:5000`** (no path rewrite; Next.js/backend likely expects `/api/...`).
4. **Postiz app:** Single service `eb24-postiz-app` (image `ghcr.io/gitroomhq/postiz-app:v2.12.1`), listening on **port 5000**.
5. **Backend:** `AuthController.register` → `AuthService.routeAuth` → `OrganizationService.createOrgAndUser`, optional `addUserToOrg`, then **`EmailService.sendEmail`** (activation email).

502 means Caddy did not get a valid response from `eb24-postiz-app:5000` for that request (timeout, connection reset, or invalid response).

---

## 3. Infrastructure Summary

- **Reverse proxy:** Caddy (config provided; runs elsewhere).
- **App:** This repo’s `docker-compose.yaml`:
  - Service: `eb24-postiz-app`
  - Image: `ghcr.io/gitroomhq/postiz-app:v2.12.1`
  - Port: 5000 (internal)
  - Depends on: `eb24-postiz-postgres`, `eb24-postiz-redis`, `eb24-postiz-temporal` (all healthy before app starts).
- **Caddy for social.eblej24.com:**
  - All traffic (including `/api/*`, `/socket.io/*`, `/uploads/*`) → `eb24-postiz-app:5000`.
  - **No** `health_checks` for this host (unlike portainer which has `/api/system/status`).
  - **No** explicit `timeout` or `dial` timeout in the reverse_proxy for Postiz.

So: **502 = upstream (Postiz) did not respond in time or crashed during the signup request.**

---

## 4. Signup Code Path (for 502 context)

- **Controller:** `apps/backend/src/api/routes/auth.controller.ts` → `POST /auth/register` → `AuthService.routeAuth(...)`.
- **Service:** `apps/backend/src/services/auth/auth.service.ts`:
  - LOCAL provider: `getUserByEmail` → `createOrgAndUser(body, ip, userAgent)` → optional `addUserToOrg` → **`sendEmail(...)`** (activation email).
- **Possible slow/failing points:**
  - **DB:** `createOrgAndUser` / Prisma (Postgres).
  - **Redis:** Session/cache usage if any during auth.
  - **Temporal:** Only if signup starts a workflow (not obvious in this path).
  - **Email:** `EmailService.sendEmail` (e.g. Resend). If `RESEND_API_KEY` is set and Resend is slow/failing, the request can hang or throw and crash the handler.
  - **Uncaught exception:** Any thrown error that isn’t caught can result in 500/502 from Caddy’s perspective if the process dies or doesn’t send a proper response.

---

## 5. Hypotheses (to validate)

| # | Hypothesis | How to check |
|---|------------|--------------|
| 1 | **Upstream timeout** – Signup (DB + email) takes longer than Caddy’s default and Caddy returns 502. | Increase Caddy `reverse_proxy` timeout for `social.eblej24.com`; check Caddy and app logs for duration of signup request. |
| 2 | **Backend crash** – Unhandled exception in register path (e.g. DB, email, validation). | Check `eb24-postiz-app` container logs (and restarts) at the time of signup. |
| 3 | **Email provider** – Resend (or other) slow/failing; request hangs or throws. | Check `RESEND_API_KEY` / email config; temporarily disable or mock email and retry signup. |
| 4 | **DB/connectivity** – Postgres slow or connection dropped during `createOrgAndUser`. | Check Postgres logs and connection limits; ensure app and DB on same network and DNS resolves (`eb24-postiz-postgres`). |
| 5 | **Temporal** – Less likely for simple signup; only if signup triggers a workflow that blocks or fails. | Check Temporal and app logs when signup is attempted. |

---

## 6. Caddy Config (relevant snippet for social.eblej24.com)

- **Host:** `social.eblej24.com`.
- **Upstream:** `eb24-postiz-app:5000` (HTTP).
- **Routes:** `/socket.io/*`, `/uploads/*`, `/api/*`, and default → same upstream.
- **No** `health_checks` for this host.
- **No** explicit `timeout` in `reverse_proxy`.

So: **Default Caddy timeouts apply.** If signup takes longer (e.g. slow email), Caddy may 502.

---

## 7. Docker Compose (relevant)

- **File:** `docker-compose.yaml` (eblej24 integration).
- **App env:** `MAIN_URL`, `FRONTEND_URL`, `NEXT_PUBLIC_BACKEND_URL` = https://social.eblej24.com (and `/api`); `DATABASE_URL`, `REDIS_URL`, `TEMPORAL_ADDRESS`; `RESEND_API_KEY`, `EMAIL_FROM_*`; `JWT_SECRET`; etc.
- **Healthcheck:** App checks `http://localhost:5000/` (HTTP 2xx). No check on `/api/auth/register`.

---

## 8. Suggested Next Steps

1. **Logs:** On the host where Docker runs, capture logs during a signup attempt:
   - `docker logs eb24-postiz-app` (and follow).
   - Optional: Caddy logs, Postgres, Redis if needed.
2. **Timeout:** In Caddy, add a longer `reverse_proxy` timeout for `social.eblej24.com` (e.g. 60s) and retry signup.
3. **Email:** If Resend is configured, try signup with a valid key and check for errors; or temporarily disable/mock email and see if 502 disappears.
4. **Reproduce:** If possible, run the same stack locally (or in a staging env) and trigger signup while watching app and DB logs.
5. **Update this file:** When you find the root cause or apply a fix, add a short “Resolution” section below with date and what changed.

---

## 9. Resolution (fill in when fixed)

- **Date:** —
- **Cause:** —
- **Fix:** —

---

---

## 10. Browser requesting :5000 (config-only fix)

**Symptom:** The browser requests `https://social.eblej24.com:5000/api/` (or navigates there), which times out or fails. Your `.env` is correct (no :5000 in `POSTIZ_*` URLs).

**Cause:** The pre-built image (`ghcr.io/gitroomhq/postiz-app:v2.12.1`) is built without `NEXT_PUBLIC_BACKEND_URL` at build time. Next.js inlines `NEXT_PUBLIC_*` into the client bundle during `next build`, so the bundle may contain a default or wrong URL (e.g. with :5000). Runtime env in the container does not change that.

**Config-only fixes (no app code changes):**

1. **Build your own image with the correct URL**  
   Use the repo’s `Dockerfile.dev` and pass build-args so the client bundle gets the right URL at build time. See `config/caddy/EBLEJ24_BUILD_AND_CADDY.md` (or docker-compose `build` + build-args in this repo). After building, run your image instead of `ghcr.io/gitroomhq/postiz-app:v2.12.1`.

2. **Caddy: handle port 5000**  
   If you cannot rebuild, expose port 5000 on the host and point it at Caddy. Add a Caddy server that listens on `:5000` for `social.eblej24.com` and reverse-proxies to `eb24-postiz-app:5000` (same as :443). Then requests to `https://social.eblej24.com:5000/api/` will be proxied and the app will respond. You must have TLS for that host on port 5000 (e.g. in the same Caddy config).

---

*This file is the single source of context for the 502-on-signup issue on social.eblej24.com. Keep it updated as the investigation progresses.*
