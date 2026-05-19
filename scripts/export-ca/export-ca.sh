#!/bin/bash

# SPDX-FileCopyrightText: 2025 Magenta ApS <https://magenta.dk>
# SPDX-License-Identifier: AGPL-3.0-only

set -e

CAROOT=$(mkcert -CAROOT)
SRC="$CAROOT/rootCA.pem"
BUNDLE="$(dirname "$0")/../../ca-bundle"

if [ ! -f "$SRC" ]; then
    echo "Error: mkcert root CA not found at $SRC"
    echo "Run 'mkcert -install' first."
    exit 1
fi

mkdir -p "$BUNDLE"
cp "$SRC" "$BUNDLE/rootCA.pem"

echo "Root CA exported to ca-bundle/rootCA.pem"
echo "Send this file to clients and have them import it manually into their browser."
