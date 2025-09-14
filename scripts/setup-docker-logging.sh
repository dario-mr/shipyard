#!/usr/bin/env bash
set -euo pipefail

LOG_MAX_SIZE=10m
LOG_MAX_FILE=5

# Detect daemon.json path (rootful vs rootless)
DAEMON_JSON="${DOCKER_DAEMON_JSON:-}"
if [[ -z "${DAEMON_JSON}" ]]; then
  if systemctl is-active --quiet docker 2>/dev/null; then
    DAEMON_JSON="/etc/docker/daemon.json"
  elif systemctl --user is-active --quiet docker 2>/dev/null; then
    # Rootless dockerd (per-user)
    DAEMON_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/docker/daemon.json"
  else
    # Fallback to rootful path
    DAEMON_JSON="/etc/docker/daemon.json"
  fi
fi

echo "Using daemon config: ${DAEMON_JSON}"

# Ensure directory exists
sudo mkdir -p "$(dirname "$DAEMON_JSON")"

# Prepare base JSON if missing
if [[ ! -f "$DAEMON_JSON" ]]; then
  echo "{}" | sudo tee "$DAEMON_JSON" >/dev/null
fi

# We need jq
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install it (apt-get install -y jq / dnf install -y jq / apk add jq) and re-run." >&2
  exit 1
fi

# Backup
sudo cp "$DAEMON_JSON" "$DAEMON_JSON.bak.$(date +%Y%m%d%H%M%S)"

# Merge settings without clobbering other keys
TMP="$(mktemp)"
sudo jq \
  --arg max_size "$LOG_MAX_SIZE" \
  --arg max_file "$LOG_MAX_FILE" \
  '
    .["log-driver"] = "json-file" |
    .["log-opts"] = (.["log-opts"] // {}) |
    .["log-opts"]["max-size"] = $max_size |
    .["log-opts"]["max-file"] = $max_file
  ' "$DAEMON_JSON" | sudo tee "$TMP" >/dev/null

sudo mv "$TMP" "$DAEMON_JSON"

# Restart docker (rootful or rootless)
if systemctl is-active --quiet docker 2>/dev/null; then
  echo "Restarting system docker.service ..."
  sudo systemctl restart docker
elif systemctl --user is-active --quiet docker 2>/dev/null; then
  echo "Restarting user docker.service (rootless) ..."
  systemctl --user restart docker
else
  # Fallbacks
  if command -v service >/dev/null 2>&1; then
    sudo service docker restart || true
  fi
  # As a last resort, try SIGHUP
  if pgrep -x dockerd >/dev/null; then
    echo "Sending HUP to dockerd ..."
    sudo kill -HUP "$(pgrep -x dockerd)"
  fi
fi

echo "Done. New containers will use json-file with rotation (${LOG_MAX_SIZE}, ${LOG_MAX_FILE})."
echo "Recreate existing containers to apply: docker compose up -d --force-recreate"