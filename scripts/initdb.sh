#!/bin/bash

# SPDX-FileCopyrightText: 2025 Magenta ApS <https://magenta.dk>
# SPDX-License-Identifier: AGPL-3.0-only

set -e

KC_DB_USERNAME=${KC_DB_USERNAME:-keycloak}
KC_DB_PASSWORD=${KC_DB_PASSWORD:-password}

psql -U "${POSTGRES_USER}" -v ON_ERROR_STOP=1 <<-EOSQL
    CREATE USER ${KC_DB_USERNAME} WITH PASSWORD '${KC_DB_PASSWORD}';
    CREATE DATABASE openstream_keycloak OWNER ${KC_DB_USERNAME};
EOSQL
