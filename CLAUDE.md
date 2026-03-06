# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository.

## Project Overview

Shipyard is a lightweight, single-host infrastructure-as-code stack based on Docker Compose. It
provides HTTPS routing, observability, and security hardening for self-hosted applications on a
single server.

**Request flow:** `Internet → Caddy (HTTPS/rate-limit) → Spring Cloud Gateway → Apps`

## Common Commands

```sh
# Start all services
docker compose up -d --build

# Check status
docker compose ps
docker compose logs -f <service>

# Recreate a single service
docker compose up -d --force-recreate --no-deps <service>

# Pull latest images and recreate
docker compose pull && docker compose up -d --force-recreate

# Clean unused images
docker image prune -f

# Validate Caddy config
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# Format Caddyfile
caddy fmt --overwrite

# Validate/format Alloy config
alloy validate observability/alloy/config.alloy
alloy fmt -w observability/alloy/config.alloy

# fail2ban: check jails / list bans / reload
docker compose exec fail2ban fail2ban-client status
docker compose exec fail2ban fail2ban-client banned
docker compose exec fail2ban fail2ban-client reload
```

## Architecture

The main `docker-compose.yml` includes modular compose files from `compose/`:

| Compose file                | Key services                                                                                |
|-----------------------------|---------------------------------------------------------------------------------------------|
| `compose.caddy.yml`         | Caddy reverse proxy (ports 80/443)                                                          |
| `compose.gateway.yml`       | Spring Cloud Gateway (port 8080, separate repo: [apigw](https://github.com/dario-mr/apigw)) |
| `compose.apps.yml`          | User-facing applications                                                                    |
| `compose.observability.yml` | Prometheus, Loki, Grafana, Alloy, cAdvisor, node-exporter, GeoIPUpdate                      |
| `compose.fail2ban.yml`      | Intrusion prevention (tails Caddy logs, bans via iptables)                                  |
| `compose.watchtower.yml`    | Automatic Docker image updates                                                              |
| `compose.portainer.yml`     | Docker management UI                                                                        |
| `compose.matrix.yml`        | Matrix/Conduit chat server + Coturn TURN server                                             |

**Networks:** `backend` (main bridge) and `wordle_duel_service_internal` (isolated for Redis).

## Key Configuration Files

- **`.env`** — All runtime config and secrets (copy from `.env.example`). Never committed.
- **`caddy/Caddyfile`** — Reverse proxy routes, security headers, rate limiting rules.
- **`observability/alloy/config.alloy`** — Log collection pipelines: Caddy access logs (JSON),
  Docker container logs, GeoIP enrichment, format detection for 11+ log types, ships to Loki.
- **`observability/prometheus/prometheus.yml`** — Metrics scrape targets. Uses Docker service
  discovery via socket proxy to auto-discover Spring Boot apps.
- **`observability/loki/loki.yml`** — Log storage config (filesystem backend, 30-day retention).
- **`observability/grafana/dashboards/`** — Pre-built Grafana dashboards (JSON).
- **`fail2ban/jail.d/caddy.local`** — Ban rules for 429s, bad paths, unknown paths. Escalating ban
  times.
- **`matrix/conduit/conduit.toml.template`** — Matrix config template. Requires `envsubst` to
  generate final config (see DOCUMENTATION.md).

## Caddy Custom Image

Caddy uses a custom Docker image with the `caddy-ratelimit` plugin built via xcaddy. The Dockerfile
is at `caddy/Dockerfile.caddy`, published as `dariomr8/caddy-with-ratelimit` on Docker Hub. To
rebuild:

```sh
docker buildx build --platform linux/arm64 \
  -t docker.io/dariomr8/caddy-with-ratelimit:2.10.2 \
  -f caddy/Dockerfile.caddy --push caddy
```