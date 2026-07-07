#!/bin/bash

# Installs a systemd service that runs the OpenStream Docker Compose stack and
# starts it automatically on boot. Re-runnable: it overwrites any existing unit
# and reloads systemd. Use --uninstall to remove the service again.

set -e

SERVICE_NAME="openstream"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# Project root is the parent of this script's directory, resolved to an
# absolute path (systemd requires an absolute WorkingDirectory).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
if [ "$1" = "--uninstall" ]; then
    echo "Removing the ${SERVICE_NAME} service..."
    sudo systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
    sudo rm -f "$UNIT_PATH"
    sudo systemctl daemon-reload
    echo "Done. The stack will no longer start on boot."
    echo "(Any running containers were stopped. Data under data/ is untouched.)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
echo "Checking prerequisites..."
missing=0

# Docker with Compose v2
if docker compose version >/dev/null 2>&1; then
    echo "  [OK]      docker compose"
else
    echo "  [MISSING] docker compose — see https://docs.docker.com/engine/install/ubuntu/"
    missing=1
fi

# systemd
if command -v systemctl >/dev/null 2>&1; then
    echo "  [OK]      systemd"
else
    echo "  [MISSING] systemd — this script targets systemd-based systems (e.g. Ubuntu Server)"
    missing=1
fi

# SERVER_IP must be configured (from the environment or the project-root .env)
ENV_FILE="$ROOT/.env"
if [ -z "$SERVER_IP" ] && [ -f "$ENV_FILE" ]; then
    SERVER_IP=$(grep -E '^SERVER_IP=' "$ENV_FILE" | tail -n1 | cut -d= -f2-)
fi
if [ -n "$SERVER_IP" ]; then
    echo "  [OK]      SERVER_IP ($SERVER_IP)"
else
    echo "  [MISSING] SERVER_IP — set it in .env (SERVER_IP=<YOUR_IP>) before installing the service"
    missing=1
fi

# TLS certificate should exist, otherwise nginx will fail to start
if [ -f "$ROOT/certs/cert.pem" ] && [ -f "$ROOT/certs/key.pem" ]; then
    echo "  [OK]      TLS certificate (certs/cert.pem)"
else
    echo "  [MISSING] TLS certificate — run 'bash scripts/setup-tls-ubuntu.sh' first"
    missing=1
fi

if [ "$missing" -ne 0 ]; then
    echo
    echo "One or more prerequisites are missing. Resolve them and re-run this script."
    exit 1
fi

# Resolve the absolute path to the docker binary; systemd runs without a login
# shell, so ExecStart cannot rely on $PATH lookups.
DOCKER_BIN="$(command -v docker)"

echo
echo "All prerequisites satisfied."

# ---------------------------------------------------------------------------
# Write the systemd unit
# ---------------------------------------------------------------------------
echo
echo "Installing systemd service at ${UNIT_PATH}..."

sudo tee "$UNIT_PATH" >/dev/null <<EOF
# Managed by scripts/install-service-ubuntu.sh — re-running that script
# overwrites this file.

[Unit]
Description=OpenStream on-premise stack (Docker Compose)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${ROOT}
# Refresh images if the registry is reachable, then run the stack in the
# foreground so systemd tracks the process, captures logs
# (journalctl -u ${SERVICE_NAME}), and can restart it on failure. The '-'
# prefix makes the pull best-effort: if the server boots offline, startup
# still proceeds with the images already present locally.
ExecStartPre=-${DOCKER_BIN} compose pull --quiet
ExecStart=${DOCKER_BIN} compose up
ExecStop=${DOCKER_BIN} compose down
Restart=always
RestartSec=10
# Give containers time to stop gracefully before systemd kills the process.
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF

# ---------------------------------------------------------------------------
# Enable and start
# ---------------------------------------------------------------------------
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}.service"
sudo systemctl restart "${SERVICE_NAME}.service"

echo
echo "Done. The OpenStream stack is now enabled and will start on boot."
echo
echo "Useful commands:"
echo "  sudo systemctl status ${SERVICE_NAME}     # check status"
echo "  sudo journalctl -u ${SERVICE_NAME} -f     # follow logs"
echo "  sudo systemctl stop ${SERVICE_NAME}       # stop the stack"
echo "  sudo systemctl start ${SERVICE_NAME}      # start the stack"
echo "  bash scripts/install-service-ubuntu.sh --uninstall   # remove the service"
