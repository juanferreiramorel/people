# Production deployment (Dokploy)

The API is served at **https://people.lanzapy.com** from a Dokploy **Compose** application built from [`compose.prod.yaml`](../compose.prod.yaml).

## Architecture

| Piece | What it does |
|---|---|
| Dokploy Compose app | Builds and runs `compose.prod.yaml` from the `main` branch. Auto-deploy is enabled, so every push to `main` redeploys. |
| `init-data` service | One-shot job (`restart: "no"`). If `data/ruc.db` exists it prints `ruc.db present, skipping build` and exits 0. Otherwise it downloads the DNIT RUC files, builds `ruc.db` and checks that the `ruc` table has more than 1,000,000 rows. Limits: 1 CPU / 1 GB. |
| `web` service | FastAPI/uvicorn on port 3000. Starts only after `init-data` completes successfully. Refuses to start if `JWT_SECRET` is missing or shorter than 32 characters. Limits: 1 CPU / 768 MB. |
| `people_data` volume | Named volume mounted at `/code/data` by both services. Holds `ruc.db`, `personas.db` and `tmp/`. |
| `people_internal` network | Private bridge network for the stack. |
| `dokploy-network` network | External network shared with Traefik. Only `web` joins it. |

Security properties:

- **No host ports.** Nothing is published with `ports:`. Traefik reaches `web` over `dokploy-network`; Dokploy generates the routing and TLS labels from the domain configured in the UI.
- **Non-root.** Containers run as uid/gid `1001`.
- **Docs disabled.** `/docs`, `/redoc` and `/openapi.json` return 404 (`ENABLE_DOCS=false`).
- **JWT required** on every data endpoint. `GET /health` is public and returns `200 {"status":"ok"}` only when the `ruc` table is readable, otherwise `503 {"status":"unavailable"}`. The container healthcheck uses it.
- **No JRE in the image.** The DNIT legal-entities archive currently ships an `.xls` file, parsed by pandas/xlrd. `tabula-py` (Java) is only used if the archive contains a PDF. If DNIT goes back to PDF, `init-data` will fail and `default-jre-headless` must be added to the `runner` stage of the `Dockerfile`.

## Environment variables

Set these in Dokploy (Compose app > **Environment**). Never commit values.

| Name | Required | Notes |
|---|---|---|
| `JWT_SECRET` | Yes | At least 32 characters. Generate with `openssl rand -hex 32`. The deploy fails if it is unset. |
| `ENABLE_DOCS` | No | Fixed to `false` in `compose.prod.yaml`. |
| `RUC_DB_URL` | No | Not used in production (the database is built from DNIT data). |
| `PEOPLE_DB_URL` | No | Not used in production. |

## First deploy

1. In Dokploy, create a project (or reuse one) and add a **Compose** application.
2. Source: the GitHub repository, branch `main`, compose path `./compose.prod.yaml`. Enable auto-deploy.
3. Environment: add `JWT_SECRET=<output of openssl rand -hex 32>`.
4. Deploy. The first deploy runs the DNIT crawl in `init-data` and takes several minutes. Follow it in the deployment logs.
5. Domains: add `people.lanzapy.com` → service `web`, container port `3000`, HTTPS enabled, certificate provider Let's Encrypt.
6. DNS (Cloudflare): create an `A` record for `people` pointing to the server, proxied. Use SSL/TLS mode **Full (strict)** once the certificate is issued.
7. If the route does not answer, reload Traefik from Dokploy (Settings > Web Server > Traefik > Reload).
8. Check: `curl https://people.lanzapy.com/health` returns `{"status":"ok"}`, and a data request without a token returns `401`.

## Issuing a client token

Run inside the running `web` container (Dokploy terminal, or SSH on the server):

```bash
docker exec <web container> python manage.py token --sub android-app --days 365
```

The token is printed once. Hand it to the client through a private channel and never commit it. Clients send it as `Authorization: Bearer <token>`.

## Rotating the secret

Changing `JWT_SECRET` invalidates **every** token issued so far.

1. Generate a new value (`openssl rand -hex 32`) and replace it in the Dokploy environment.
2. Redeploy.
3. Reissue tokens for every client (see above) and update them.

## Refreshing the DNIT data

`init-data` skips the build when `ruc.db` exists, so a refresh must be explicit. Run it from the server, in the directory where Dokploy checked out the compose app, using the one-shot service (it has the 1 GB memory limit the crawler needs):

- Rebuild over the existing database:

  ```bash
  docker compose -p <compose project> -f compose.prod.yaml run --rm init-data build
  ```

- Or delete the database and let `init-data` rebuild and validate it (row-count check):

  ```bash
  docker exec <web container> rm /code/data/ruc.db
  docker compose -p <compose project> -f compose.prod.yaml run --rm init-data
  ```

The crawl downloads files for several minutes first; the `ruc` table is then dropped and re-inserted, so lookups (and `/health`) fail briefly at the end of the build. After the delete-and-rebuild path, restart `web` (`docker compose -p <compose project> -f compose.prod.yaml restart web`) so no connection keeps pointing at the deleted file.

## Rollback

In Dokploy, open the Compose app > **Deployments** and redeploy the previous successful commit (or revert the commit on `main` and push). The data volume is not touched by a rollback.

## Backups

None needed. The data is public (DNIT) and fully reproducible with `init-data`/`build`. There is nothing else to back up off-server; the only secret is `JWT_SECRET`, which lives in Dokploy.

## Known limitations

- Python 3.8 is end-of-life. The pinned dependency set (FastAPI 0.66, pandas 1.3.5) needs an upgrade before moving to a supported Python.
- Pending: a scheduled weekly refresh of the DNIT data (for example a server cron or Dokploy schedule running the `run --rm init-data build` command above).
- The DNIT download format can change without notice (see the JRE note above).

## Shared-server rules

This server hosts other applications.

- **Never** run `docker system prune`, `docker volume prune`, `docker image prune -a` or `docker network prune`.
- Only operate on this stack's own containers, volumes and networks. Never remove `dokploy-network`.
- Do not publish host ports; route everything through Traefik.
