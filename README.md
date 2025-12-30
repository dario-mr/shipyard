# shipyard

A lightweight, single-host infrastructure-as-code stack for small projects, based on Docker Compose.

Opinionated defaults, with clear entrypoints and configuration that are easy to customize.

**What you get**

- HTTPS at the edge (Caddy + Let’s Encrypt)
- Central routing (Spring Cloud Gateway)
- Observability (Alloy + Loki + Prometheus + Grafana)
- Basic hardening (security headers, rate limiting, fail2ban)

## Contents

- [Architecture](#architecture)
- [Components](#components)
- [Prerequisites](#prerequisites)
- [Quickstart](#quickstart)
- [Configuration](#configuration)
- [Operations](#operations)
- [Minimal security notes](#minimal-security-notes)

## Architecture

Request path: `Internet → Caddy → Gateway → Apps`

```mermaid
%%{ init: { "flowchart": { "nodeSpacing": 50, "rankSpacing": 50 } } }%%
flowchart TD
    Internet["Internet"]

    subgraph Public["Public"]
        Caddy["Caddy<br/>[reverse proxy]"]
    end

    subgraph Internal["Internal (Docker network)"]
        subgraph Core["Core"]
            Gateway["Gateway<br/>[routing]"]
            Apps["Apps"]
        end

        subgraph Observability["Observability"]
            Prometheus["Prometheus<br/>[metrics scraper & db]"]
            Alloy["Alloy<br/>[log agent]"]
            Loki["Loki<br/>[log db]"]
            Grafana["Grafana<br/>[dashboards]"]
        end

        subgraph Security["Security"]
            fail2ban["fail2ban<br/>[intrusion prevention]"]
        end
    end

%% traffic
    Internet --> Caddy
    Caddy -->|forwards to| Gateway
    Gateway -->|routes to| Apps
%% security
    fail2ban -->|tails access logs| Caddy
%% observability
    Alloy -->|tails access logs| Caddy
    Alloy -->|tails container logs| Apps
    Alloy -->|ships logs| Loki
    Grafana -->|queries logs| Loki
%% metrics
    Prometheus -->|scrapes metrics| Apps
    Grafana -->|queries metrics| Prometheus
%% colors
    style Public fill: #fff7ed, stroke: #fed7aa
    style Internal fill: #f0f9ff, stroke: #bae6fd
    style Core fill: #fff7ed, stroke: #fed7aa
    style Observability fill: #e0f2fe, stroke: #93c5fd
    style Security fill: #e0f2fe, stroke: #93c5fd
%% normal nodes
    classDef node fill: #bae6fd, stroke: #60a5fa, color: #0f172a
    class Prometheus,Alloy,Loki,Grafana,fail2ban node
%% main-flow nodes
    classDef mainFlow fill: #ffedd5, stroke: #fdba74, color: #7c2d12
    class Internet,Caddy,Gateway,Apps mainFlow
```

## Components

- **Caddy**: HTTPS, rate limiting, security headers, reverse proxy to `Gateway`.
- **Gateway**: Spring Cloud Gateway (separate repo: [`apigw`](https://github.com/dario-mr/apigw))
  that routes to upstream apps.
- **fail2ban**: tails Caddy logs and bans offenders at firewall level.
- **Observability**:
    - **Alloy**: tails Caddy access logs and application logs (from Docker stdout) and ships them to Loki.
    - **Loki**: log database.
    - **Prometheus**: scrapes and stores metrics from Spring Boot apps and infra services.
    - **Grafana**: dashboards for logs (Loki) and metrics (Prometheus), served under `/grafana/`.
- **Watchtower**: auto-pulls the latest Docker images.
- **Portainer**: Docker UI, served under `/portainer/`.
- **Apps**: `api-stress-test`, `ichiro-family-tree`, etc.

## Prerequisites

- A domain name pointing to the server’s IP (for TLS/Let’s Encrypt).
- A server with Docker and Docker Compose.
- Firewall allows inbound `80/tcp` and `443/tcp`.
- If you enable Matrix + Coturn (private chat and calls), you also need `3478/tcp`, `3478/udp`, and
  a UDP port range (see `DOCUMENTATION.md`).

## Quickstart

```sh
# 1) Clone repo
git clone https://github.com/dario-mr/shipyard.git
cd shipyard

# 2) Open required ports (SSH, HTTP/HTTPS, COTURN)
./scripts/open-ports.sh

# 3) Configure Docker log rotation (requires sudo + jq)
./scripts/setup-docker-logging.sh

# 4) Create your env file
cp .env.example .env
# edit values

# 5) Start
docker compose up -d --build

# 6) Verify
docker compose ps
docker compose logs -f caddy
```

**Access (after DNS + TLS are working)**

- Grafana: `https://<your-domain>/grafana/`
- Portainer: `https://<your-domain>/portainer/`

## Configuration

- `.env` contains runtime configuration and secrets. Start from `.env.example`.
- Treat these as secrets and do not commit them:
    - `GRAFANA_ADMIN_PASSWORD`
    - `EMAIL_SERVER_PASSWORD`: used for watchtower notifications
    - `GEOIPUPDATE_ACCOUNT_ID`, `GEOIPUPDATE_LICENSE_KEY`: GeoIP data to enrich access logs, get your free
      key at [MaxMind](https://www.maxmind.com/en/geolite2/signup)
    - `CONDUIT_REGISTRATION_TOKEN`, `TURN_SECRET`: only if you enable Matrix
- App configs:
    - `DOMAIN`, `TIMEZONE`
    - DB / OAuth settings for your apps

## Operations

See [Operations & troubleshooting](DOCUMENTATION.md#operations--troubleshooting) for
service-specific notes.

## Backups

This stack uses named Docker volumes (see `docker-compose.yml`). If you care about persistence, back
up at least:

- `caddy_data`, `caddy_config`
- `grafana_data`, `prometheus_data`, `loki_data`
- `portainer_data`
- `conduit-data` (only if you enable Matrix)

## Minimal security notes

This stack is meant to be exposed to the public internet.

- Caddy terminates TLS and applies basic hardening (headers + rate limiting).
- fail2ban bans abusive IPs based on Caddy logs.
- You should still review configs, rotate secrets, and keep images updated before running this on a
  real domain.
