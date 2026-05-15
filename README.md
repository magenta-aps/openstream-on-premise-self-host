# OpenStream — On-Premise Deployment

Docker Compose setup for running OpenStream on a local on-premise server using pre-built images from Docker Hub. No development tools or source code required.

## Prerequisites

- Docker with Compose v2 (`docker compose`)
- [mkcert](https://github.com/FiloSottile/mkcert) for generating TLS certificates

## First-time setup

### 1. Set the server IP

Create `.env` in the project root and set `SERVER_IP` to the IP address of the server:

```
SERVER_IP=192.168.1.100
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

Run these commands from the `openstream-deploy/` directory:

```bash
mkcert -install
mkcert -cert-file certs/cert.pem -key-file certs/key.pem <SERVER_IP>
```

Replace `<SERVER_IP>` with the same IP set in `.env`. The `certs/` directory is already created.

To allow other machines to trust this certificate, distribute the root CA:

```bash
cat "$(mkcert -CAROOT)/rootCA.pem"
```

Import that certificate into the trust store of each client machine. On Linux:

```bash
sudo cp rootCA.pem /usr/local/share/ca-certificates/openstream.crt
sudo update-ca-certificates
```

### 4. Pre-create data directories with correct ownership

PostgreSQL and MinIO run as non-root users and will fail if the data directories are owned by root:

```bash
sudo chown 999:999 data/postgres
sudo chown 1000:1000 data/minio
```

This only needs to be done once before the first run.

### 5. Start the stack

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

## Updating to a new version

Edit `compose.yml` and change the image tags for `openstream`, `openstream-frontend`, and `openstream-polling`, then pull and restart:

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

