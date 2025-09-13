# shipyard
Infrastructure-as-code for my self-hosted stack (Docker Compose + Caddy).

## Components

- **Caddy**: automatic HTTP → HTTPS redirect, rate limiting, security headers, reverse-proxy to
  Gateway.
- **Gateway**: Spring Cloud Gateway that routes requests to the right upstream apps.
- **fail2ban**: watches caddy logs for bad behavior patterns and then blocks the IP at firewall
  level.
- **Watchtower**: automatically pull new docker images.
- **Portainer**: dashboard to manage docker containers. Served under `/portainer/`.
- **Observability**:
    - **Promtail**: tails Caddy's access logs, parses fields, enriches with GeoIP data, and ships to
      Loki. The GeoIP DB is automatically updated by the `geoipupdate` service.
    - **Loki**: log database storing the ingested logs.
    - **Grafana**: dashboards querying Loki for access logs. Served under `/grafana/`.
- **Backends**: `api-stress-test`, `ichiro-family-tree`, etc.

## How to run

1. Make sure your domain (e.g. `dariolab.com`) is pointing to your server's IP.
2. Copy [.env.example](.env.example) to `.env` and edit the variables as needed.
3. (Optional) Edit the config files if needed:
    - [docker-compose.yml](docker-compose.yml): orchestrates the whole stack (Caddy, gateway, and
      backend services), networking, and volume persistence.
    - [Caddyfile](caddy/Caddyfile): defines the public domain, TLS/Let’s Encrypt setup, rate limits,
      security headers, and
      reverse-proxy rules into the gateway.
      prefixes, forwarding logic, and upstream service addresses.
    - [ban rules](fail2ban/jail.d/caddy.local): configures IP banning rules.

4. Start everything:
   ```shell
   docker compose up -d --build
   ```

## Caddy image

The app uses a custom caddy image that includes the `caddy-ratelimit` plugin. It is hosted in
my [docker hub](https://hub.docker.com/repository/docker/dariomr8/caddy-with-ratelimit/general).

It is built from the [Dockerfile.caddy](caddy/Dockerfile.caddy).

To update the image after editing the Dockerfile:

```shell
docker login docker.io

docker buildx build \
  --platform linux/arm64 \
  -t docker.io/dariomr8/caddy-with-ratelimit:2.10.0 \
  -f Dockerfile.caddy \
  --push .
```

## Useful commands

### Logs

```shell
docker compose logs -f caddy gateway
```

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

#### filter access logs by 404, grouped by IP and path

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

#### filter access logs by 404, sorted by number of hits

```shell
docker compose exec caddy cat /var/log/caddy/access.log \
  | jq -r 'select((.resp_headers["X-Unknown-Path"]//[])[0] == "1") | .request.uri' \
  | awk '{c[$0]++} END {for (u in c) print c[u] "\t" u}' \
  | sort -t $'\t' -k1,1nr
```

#### filter access logs by 429

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