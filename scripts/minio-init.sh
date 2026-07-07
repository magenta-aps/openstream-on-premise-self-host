#!/bin/sh

set -e

until mc alias set local http://minio:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"; do
    echo "Waiting for MinIO..."
    sleep 1
done

mc mb --ignore-existing local/infoscreen
mc anonymous set download local/infoscreen

echo "MinIO configured successfully."
