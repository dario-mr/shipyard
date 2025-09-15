# shipyard

Infrastructure-as-code for my self-hosted stack (Docker Compose + Caddy).

Caddy reverse proxy at the edge, Spring Cloud Gateway in the middle, observability and hardening
around it.

## Architecture

```plaintext
Internet ──▶ Caddy ──▶ Gateway ───▶ Backends
               │
               │
               ├─────▶ Promtail ──▶ Loki ────┐
               │        (logs)               │
               │                             ├───▶ Grafana
               │                             │
               ├─────▶ Prometheus ───────────┘
               │       (metrics)
               │
               └─────▶ fail2ban
```

## Components

- **Caddy**: HTTPS, rate limiting, security headers, reverse proxy to `Gateway`.
- **Gateway**: Spring Cloud Gateway (separate repo: [apigw](https://github.com/dario-mr/apigw)) that
  routes to upstream apps.
- **fail2ban**: watches Caddy logs and bans offenders at firewall level.
- **Watchtower**: auto-pull the latest docker images.
- **Portainer**: Docker UI, served under `/portainer/`.
- **Observability**:
    - **Promtail**: ships Caddy and application logs to Loki.
    - **Loki**: log database queried by Grafana.
    - **Prometheus**: scrapes metrics from:
        - Spring Boot apps
        - Prometheus itself, Loki, and Promtail
    - **Grafana**: dashboards for **logs** (Loki) and **metrics** (Prometheus), served under
      `/grafana/`.
- **Backends**: `api-stress-test`, `ichiro-family-tree`, etc.

## Pre-requisites

- A domain name pointing to the server's IP (for TLS/Let’s Encrypt).
- A server with Docker and Docker Compose installed.

## How to run

```shell
# 1. (Optional) Setup docker logging driver to use json-file with log rotation
./scripts/setup-docker-logging.sh

# 2. Copy & edit env file
cp .env.example .env
# edit values

# 3. Bring the stack up
docker compose up -d --build

# 4. Verify
docker compose ps
docker compose logs -f caddy
```

## Caddy image

Caddy uses a custom image that includes the `caddy-ratelimit` plugin. It is hosted in
my [docker hub](https://hub.docker.com/repository/docker/dariomr8/caddy-with-ratelimit/general).

It is built from the [Dockerfile.caddy](caddy/Dockerfile.caddy).

To update the image after editing the Dockerfile:

```shell
docker login docker.io

cd caddy
docker buildx build \
  --platform linux/arm64 \
  -t docker.io/dariomr8/caddy-with-ratelimit:2.10.0 \
  -f Dockerfile.caddy \
  --push .
```

## Useful commands

### Recreate containers

```shell
docker compose pull

docker compose up -d --force-recreate
docker compose up -d --force-recreate --no-deps gateway
docker compose --env-file .env up -d --force-recreate --no-deps gateway
```

### Clean unused images

```shell
docker image prune -f
```

### Caddy

#### format

```shell
caddy fmt --overwrite
```

#### validate

```shell
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

### Caddy access log helpers

#### 404s grouped by IP and path

```shell
docker compose exec caddy cat /var/log/caddy/access.log \
  | jq -r 'select((.resp_headers["X-Unknown-Path"]//[])[0] == "1")
           | [.request.remote_ip, .request.uri] | @tsv' \
  | awk -F'\t' '{c[$1 FS $2]++} END {for (k in c) print c[k] "\t" k}' \
  | sort -t $'\t' -k2,2 -k1,1nr \
  | awk -F'\t' 'BEGIN{ip=""} {
        if ($2 != ip) { if (ip != "") print ""; ip=$2; print ip }
        printf "    %5d  %s\n", $1, $3
    }'
```

#### 404s sorted by hits

```shell
docker compose exec caddy cat /var/log/caddy/access.log \
  | jq -r 'select((.resp_headers["X-Unknown-Path"]//[])[0] == "1") | .request.uri' \
  | awk '{c[$0]++} END {for (u in c) print c[u] "\t" u}' \
  | sort -t $'\t' -k1,1nr
```

#### 429s

```shell
docker compose exec caddy cat /var/log/caddy/access.log | jq -r 'select(.status == 429) | .request.uri'
```

### fail2ban

```shell
# reload configs (e.g.: after changing fail2ban/jail.d/caddy.local)
docker compose exec fail2ban fail2ban-client reload

# check jails
docker compose exec fail2ban fail2ban-client status
docker compose exec fail2ban fail2ban-client status caddy-429
docker compose exec fail2ban fail2ban-client status caddy-badpaths
docker compose exec fail2ban fail2ban-client status caddy-unknownpaths

# list banned IPs
docker compose exec fail2ban fail2ban-client banned

# unban
docker compose exec fail2ban fail2ban-client set caddy-429 unbanip 86.49.248.100
docker compose exec fail2ban fail2ban-client set caddy-unknownpaths unbanip 86.49.248.100
```