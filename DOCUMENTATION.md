# Documentation

See `README.md` for the high-level overview.

## Caddy custom image

Caddy uses a custom image that includes the `caddy-ratelimit` plugin.

- Docker
  Hub: [dariomr8/caddy-with-ratelimit](https://hub.docker.com/repository/docker/dariomr8/caddy-with-ratelimit/general)
- Dockerfile: [`caddy/Dockerfile.caddy`](caddy/Dockerfile.caddy)

To update the image after editing the Dockerfile:

```sh
docker login docker.io

docker buildx build \
  --platform linux/arm64 \
  -t docker.io/dariomr8/caddy-with-ratelimit:2.10.0 \
  -f caddy/Dockerfile.caddy \
  --push caddy
```

## Matrix

### Conduit (chat server)

Conduit does not expand environment variables inside `conduit.toml`.
To keep secrets out of git, we generate the final config using `envsubst` at deploy time.

**Files**

- `matrix/conduit/conduit.toml.template` — committed template
- `compose/conduit/generated/conduit.toml` — generated file (not committed)
- `.env` — contains secrets (not committed)

**Required environment variables**

- `DOMAIN`
- `CONDUIT_REGISTRATION_TOKEN`
- `TURN_SECRET`

**Generate the config**

Run from the repo root:

```sh
mkdir -p compose/conduit/generated
set -a; . ./.env; set +a
envsubst < matrix/conduit/conduit.toml.template > compose/conduit/generated/conduit.toml
```

**Start / update the service**

```sh
docker compose up -d --force-recreate --no-deps conduit
```

**When to re-run `envsubst`**

Re-run the generation step if you change `.env`, `conduit.toml.template`, the domain, or the
registration token.

## Operations & troubleshooting

### Recreate containers

```sh
docker compose pull
docker compose up -d --force-recreate
docker compose up -d --force-recreate --no-deps gateway
docker compose --env-file .env up -d --force-recreate --no-deps gateway
```

### Clean unused images

```sh
docker image prune -f
```

### Caddy

Format:

```sh
caddy fmt --overwrite
```

Validate:

```sh
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

### Caddy access log helpers

These assume the Caddy access log is at `/var/log/caddy/access.log` and `jq` is installed.

#### 404s grouped by IP and path

```sh
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

```sh
docker compose exec caddy cat /var/log/caddy/access.log \
  | jq -r 'select((.resp_headers["X-Unknown-Path"]//[])[0] == "1") | .request.uri' \
  | awk '{c[$0]++} END {for (u in c) print c[u] "\t" u}' \
  | sort -t $'\t' -k1,1nr
```

#### 429s (too many requests)

```sh
docker compose exec caddy cat /var/log/caddy/access.log | jq -r 'select(.status == 429) | .request.uri'
```

### fail2ban

```sh
# reload configs (e.g. after changing fail2ban/jail.d/caddy.local)
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
