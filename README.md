# OpenStream — On-Premise Deployment

Docker Compose setup for running OpenStream on a local on-premise server using pre-built images from Docker Hub. No development tools or source code required.

## Prerequisites

- Docker with Compose v2 (`docker compose`)
- [mkcert](https://github.com/FiloSottile/mkcert) for generating TLS certificates

On Ubuntu Server (tested on 24.04), install both mkcert and its `libnss3-tools` dependency (required for `mkcert -install` to work correctly):

```bash
sudo apt update
sudo apt install mkcert libnss3-tools
```

For Docker with Compose v2, follow the official [Docker Engine install guide for Ubuntu](https://docs.docker.com/engine/install/ubuntu/).



## First-time setup

### 1. Set the server IP

Create `.env` in the project root and set `SERVER_IP` to the IP address of the server:

```
SERVER_IP=<YOUR_IP>
```

This is the only place you need to define it — all services pick it up automatically.

### 2. Set passwords

Replace all placeholder secrets across the env files — every `changeme…` value plus `DJANGO_SECRET_KEY` (whose placeholder is `change-this-to-a-long-random-string`). The comments in each file indicate which values must match across files:

| File | Secrets |
|---|---|
| `env/db.env` | `POSTGRES_PASSWORD`, `KC_DB_PASSWORD` |
| `env/backend.env` | `DJANGO_SECRET_KEY`, `DATABASE_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD`, `AWS_S3_SECRET`, `COLLAB_SERVER_API_KEY` |
| `env/keycloak.env` | `KC_BOOTSTRAP_ADMIN_PASSWORD`, `KC_DB_PASSWORD` |
| `env/minio.env` | `MINIO_ROOT_PASSWORD` |
| `env/polling.env` | `PGPASSWORD` |

Because the same secret is shared by several services, some values must be **identical** across files (the file comments flag each one):

| Shared secret | Must match across |
|---|---|
| PostgreSQL app password | `POSTGRES_PASSWORD` (db.env) · `DATABASE_PASSWORD` (backend.env) · `PGPASSWORD` (polling.env) |
| Keycloak DB password | `KC_DB_PASSWORD` (db.env) · `KC_DB_PASSWORD` (keycloak.env) |
| Keycloak admin password | `KEYCLOAK_ADMIN_PASSWORD` (backend.env) · `KC_BOOTSTRAP_ADMIN_PASSWORD` (keycloak.env) |
| MinIO / S3 secret | `AWS_S3_SECRET` (backend.env) · `MINIO_ROOT_PASSWORD` (minio.env) |
| Collab API key | `COLLAB_SERVER_API_KEY` (backend.env) · `COLLAB_SERVER_API_KEY` (compose.yml, `collab-server` service) |

> **Note:** the Collab API key is the one secret set in `compose.yml` rather than an env file. If the two values differ, multiplayer editing fails to authorize.

### 3. Generate a TLS certificate

On Ubuntu, run the setup script from the project root. It checks the prerequisites (Docker Compose, mkcert, libnss3-tools, and `SERVER_IP`), generates the certificate into `certs/`, and exports the root CA to `ca-bundle/rootCA.pem`:

```bash
bash scripts/setup-tls-ubuntu.sh
```

<details>
<summary>Or do it manually</summary>

Create a `certs/` folder in the project root, then run these commands from the project root:

```bash
mkcert -install
mkcert -cert-file certs/cert.pem -key-file certs/key.pem <SERVER_IP>
```

Replace `<SERVER_IP>` with the same IP set in `.env`.

To distribute the root CA to other clients, run:

```bash
bash scripts/export-ca/export-ca.sh
```

This copies the root CA into `ca-bundle/rootCA.pem`.
</details>

Once the stack is running (step 6), clients can download the root CA straight from the server instead of receiving the file by hand:

```
http://<SERVER_IP>/rootCA.pem
```

This is served over plain **HTTP** on purpose, so a client that does not yet trust the CA can fetch it without hitting a certificate warning. The same file is also available at `https://<SERVER_IP>/rootCA.pem` once the CA is trusted. (You can still copy `ca-bundle/rootCA.pem` to clients manually if you prefer.)

#### Importing the CA in a browser

**Chrome/Edge:** Go to `Settings → Privacy and security → Security → Manage certificates → Authorities` and import `rootCA.pem`.

**Firefox (and Firefox-based browsers like Zen):** Go to `Settings → Privacy & Security → View Certificates → Authorities → Import` and import `rootCA.pem`.

#### Kiosk devices

For kiosk devices running Chrome or Chromium you can bypass TLS validation entirely with a flag instead of importing the CA:

```bash
chromium-browser --kiosk --ignore-certificate-errors https://<SERVER_IP>/connect-screen?apiKey=<BRANCH_API_KEY>
```

### 4. Configure realms

Edit `realms.json` in the project root to define the organisations, sub-organisations, branches, and users that OpenStream will provision on startup. The file is mounted read-only into the container and processed by an idempotent command on every startup, so it is safe to leave `REALM_CONFIG_FILE` set after the first run.

The file is a JSON array where each element is a realm (organisation):

```json
[
  {
    "uri": "my-org",
    "name": "My Organisation",
    "suborganisations": [
      {
        "name": "Department A",
        "branches": ["Branch 1", "Branch 2"]
      }
    ],
    "users": [
      {
        "username": "org_admin",
        "password": "change_me",
        "kc_role": "org_admin",
        "first_name": "Organisation",
        "last_name": "Admin",
        "roles": [
          { "role": "org_admin" }
        ]
      },
      {
        "username": "alice",
        "password": "change_me",
        "kc_role": "org_user",
        "first_name": "Alice",
        "last_name": "Jensen",
        "roles": [
          {
            "role": "employee",
            "suborganisation": "Department A",
            "branch": "Branch 1"
          }
        ]
      }
    ]
  }
]
```

**Field reference**

| Field | Required | Description |
|---|---|---|
| `uri` | yes | Unique URL-safe slug for the organisation (e.g. `my-org`) |
| `name` | yes | Display name |
| `suborganisations` | no | Additional sub-organisations to create. A "Global" sub-org is always created automatically regardless of this list |
| `suborganisations[].name` | yes | Sub-organisation name, unique within the realm |
| `suborganisations[].branches` | no | List of branch name strings within the sub-organisation |
| `users[].username` | yes | Login username, unique within the realm |
| `users[].password` | yes | Initial password (also set in Keycloak) |
| `users[].kc_role` | yes | Keycloak role: `org_admin` or `org_user` |
| `users[].first_name` | no | |
| `users[].last_name` | no | |
| `users[].roles` | no | Application-level role assignments (see table below) |

**Application roles (`users[].roles[].role`)**

| Role | `suborganisation` | `branch` |
|---|---|---|
| `super_admin` | — | — |
| `org_admin` | — | — |
| `suborg_admin` | required | — |
| `branch_admin` | required | required |
| `employee` | required | required |

### 5. Pre-create data directories with correct ownership

PostgreSQL and MinIO run as non-root users and will fail if their data directories are owned by root. The `data/` directory is not part of the repository, so create the directories first, then set the correct ownership:

```bash
mkdir -p data/postgres data/minio
sudo chown 999:999 data/postgres
sudo chown 1000:1000 data/minio
```

This only needs to be done once before the first run.

### 6. Start the stack

```bash
docker compose up 
```

On first run, the database is initialized and all migrations are applied automatically. Keycloak may take up to 30 seconds to start.

## Service URLs

Once running, the services are available at:

| Service | URL |
|---|---|
| Frontend | `https://SERVER_IP` |
| Backend API | `https://SERVER_IP:8443` |
| Keycloak | `https://SERVER_IP:8080` |
| MinIO (S3 API) | `https://SERVER_IP:9443` |
| MinIO Console | `https://SERVER_IP:9444` |
| Polling (SSE) | `https://SERVER_IP:3000` |
| Collab (WebSocket) | `wss://SERVER_IP:3001` |

## Updating to a new version

Edit `compose.yml`, change the image tags to the new version, then pull and restart:

```bash
docker compose pull
docker compose up -d
```

The application images share one version tag — update all of them together:

- `magentaaps/openstream` — referenced **twice**, by both the `openstream` and `cron` services; update both tags, or the cron worker keeps running the old version
- `magentaaps/openstream-frontend`
- `magentaaps/openstream-polling`
- `magentaaps/openstream-collab`

Migrations run automatically on startup.

## Data persistence

All persistent data is stored under `data/` relative to this directory:

| Directory | Contents |
|---|---|
| `data/postgres/` | PostgreSQL database (application data + Keycloak realms) |
| `data/minio/` | Uploaded media files (images, videos, PDFs) |

