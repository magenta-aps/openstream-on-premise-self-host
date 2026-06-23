# OpenStream — On-Premise Deployment

Docker Compose setup for running OpenStream on a local on-premise server using pre-built images from Docker Hub. No development tools or source code required.

## Prerequisites

- Docker with Compose v2 (`docker compose`)
- [mkcert](https://github.com/FiloSottile/mkcert) for generating TLS certificates

## First-time setup

### 1. Set the server IP

Create `.env` in the project root and set `SERVER_IP` to the IP address of the server:

```
SERVER_IP=<YOUR_IP>
```

This is the only place you need to define it — all services pick it up automatically.

### 2. Set passwords

Replace all `changeme` values across the env files. The comments in each file indicate which values must match across files:

| File | Secrets |
|---|---|
| `env/db.env` | `POSTGRES_PASSWORD`, `KC_DB_PASSWORD` |
| `env/backend.env` | `DJANGO_SECRET_KEY`, `DATABASE_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD`, `AWS_S3_SECRET` |
| `env/keycloak.env` | `KC_BOOTSTRAP_ADMIN_PASSWORD`, `KC_DB_PASSWORD` |
| `env/minio.env` | `MINIO_ROOT_PASSWORD` |
| `env/polling.env` | `PGPASSWORD` |

### 3. Generate a TLS certificate

Create a `certs/` folder in the project root.

Then run these commands from the project root:

```bash
mkcert -install
mkcert -cert-file certs/cert.pem -key-file certs/key.pem <SERVER_IP>
```

Replace `<SERVER_IP>` with the same IP set in `.env`. The `certs/` directory is already created.

To distribute the root CA to other clients, run:

```bash
bash scripts/export-ca/export-ca.sh
```

This copies the root CA into `ca-bundle/rootCA.pem`. Send that file to each client.

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
| `suborganisations` | no | List of sub-organisations; if omitted a "Global" sub-org is created automatically |
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

PostgreSQL and MinIO run as non-root users and will fail if the data directories are owned by root:

```bash
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
| MinIO | `https://SERVER_IP:9443` |
| Polling (SSE) | `https://SERVER_IP:3000` |
| Collab (WebSocket) | `wss://SERVER_IP:3001` |

## Updating to a new version

Edit `compose.yml` and change the image tags for `openstream`, `openstream-frontend`, `openstream-polling`, and `openstream-collab`, then pull and restart:

```bash
docker compose pull
docker compose up -d
```

Migrations run automatically on startup.

## Data persistence

All persistent data is stored under `data/` relative to this directory:

| Directory | Contents |
|---|---|
| `data/postgres/` | PostgreSQL database (application data + Keycloak realms) |
| `data/minio/` | Uploaded media files (images, videos, PDFs) |

