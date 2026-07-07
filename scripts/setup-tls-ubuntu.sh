#!/bin/bash

# SPDX-FileCopyrightText: 2025 Magenta ApS <https://magenta.dk>
# SPDX-License-Identifier: AGPL-3.0-only

set -e

missing=0

echo "Checking prerequisites..."

# Docker with Compose v2
if docker compose version >/dev/null 2>&1; then
    echo "  [OK]      docker compose"
else
    echo "  [MISSING] docker compose — see https://docs.docker.com/engine/install/ubuntu/"
    missing=1
fi

# mkcert
if command -v mkcert >/dev/null 2>&1; then
    echo "  [OK]      mkcert"
else
    echo "  [MISSING] mkcert — install with 'sudo apt install mkcert'"
    missing=1
fi

# libnss3-tools (provides certutil, required by 'mkcert -install')
if command -v certutil >/dev/null 2>&1; then
    echo "  [OK]      libnss3-tools"
else
    echo "  [MISSING] libnss3-tools — install with 'sudo apt install libnss3-tools'"
    missing=1
fi

# SERVER_IP (from the environment or the project-root .env)
ENV_FILE="$(dirname "$0")/../.env"
if [ -z "$SERVER_IP" ] && [ -f "$ENV_FILE" ]; then
    SERVER_IP=$(grep -E '^SERVER_IP=' "$ENV_FILE" | tail -n1 | cut -d= -f2-)
fi
if [ -n "$SERVER_IP" ]; then
    echo "  [OK]      SERVER_IP ($SERVER_IP)"
else
    echo "  [MISSING] SERVER_IP — set it in the environment or in .env (SERVER_IP=<YOUR_IP>)"
    missing=1
fi

if [ "$missing" -ne 0 ]; then
    echo
    echo "One or more prerequisites are missing. Install them and re-run this script."
    exit 1
fi

echo
echo "All prerequisites satisfied."

# Generate the TLS certificate
ROOT="$(dirname "$0")/.."
CERTS="$ROOT/certs"

echo
echo "Generating TLS certificate for $SERVER_IP..."
mkdir -p "$CERTS"
mkcert -install
mkcert -cert-file "$CERTS/cert.pem" -key-file "$CERTS/key.pem" "$SERVER_IP"

# Export the root CA for distribution to clients
echo
echo "Exporting root CA..."
bash "$(dirname "$0")/export-ca/export-ca.sh"

echo
echo "Done."
