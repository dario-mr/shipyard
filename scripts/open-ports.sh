#!/usr/bin/env bash
set -euo pipefail

# SSH
ufw allow 22/tcp

# HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# COTURN (matrix calls)
ufw allow 3478/tcp
ufw allow 3478/udp
ufw allow 49160:49200/udp
