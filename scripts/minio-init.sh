#!/bin/sh

# SPDX-FileCopyrightText: 2025 Magenta ApS <https://magenta.dk>
# SPDX-License-Identifier: AGPL-3.0-only

set -e

until mc alias set local http://minio:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"; do
    echo "Waiting for MinIO..."
    sleep 1
done

mc mb --ignore-existing local/infoscreen
mc anonymous set download local/infoscreen

echo "MinIO configured successfully."
