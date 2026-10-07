# Backup and transfer to another server

This stack stores persistent state in two Docker volumes and a few local files:

- `docker-zitadel_data` — PostgreSQL data
- `docker-zitadel_letsencrypt` — Traefik ACME certificates
- `.env` — all secrets and domain settings
- `docker-compose.yaml` — stack definition
- `login-client.pat` — generated login PAT (optional, but useful to keep)

## Ready-made scripts

- `./backup.sh` — stops the stack and creates a full backup in `backup-YYYY-MM-DD-HHMMSS/`
- `./restore.sh <backup-directory>` — restores files and Docker volumes from a backup

Examples:

```sh
./backup.sh
./restore.sh ./backup-YYYY-MM-DD-HHMMSS
```

If you need to overwrite existing files and volumes during restore:

```sh
FORCE=1 ./restore.sh ./backup-YYYY-MM-DD-HHMMSS
```

## Recommended method: cold backup

This method is best for a full move to another server.

### 1) Stop the stack

```sh
docker compose down
```

### 2) Create a backup directory

```sh
BACKUP_DIR="$PWD/backup-$(date +%F-%H%M%S)"
mkdir -p "$BACKUP_DIR"
```

### 3) Archive local files

```sh
tar czf "$BACKUP_DIR/stack-files.tar.gz" \
  docker-compose.yaml \
  .env \
  login-client.pat
```

If `login-client.pat` does not exist, omit it.

### 4) Backup the PostgreSQL volume

```sh
docker run --rm \
  -v docker-zitadel_data:/source:ro \
  -v "$BACKUP_DIR:/backup" \
  alpine sh -c 'cd /source && tar czf /backup/docker-zitadel_data.tar.gz .'
```

### 5) Backup the Let's Encrypt volume

```sh
docker run --rm \
  -v docker-zitadel_letsencrypt:/source:ro \
  -v "$BACKUP_DIR:/backup" \
  alpine sh -c 'cd /source && tar czf /backup/docker-zitadel_letsencrypt.tar.gz .'
```

### 6) Transfer the backup directory

Copy the whole backup directory to the new server with `scp`, `rsync`, or similar.

---

## Restore on the new server

### 1) Prepare the target directory

Use the same project directory name `docker-zitadel`, or set `COMPOSE_PROJECT_NAME=docker-zitadel` before starting.

```sh
mkdir -p ~/docker-zitadel
cd ~/docker-zitadel
```

Copy the backup directory into this folder.

### 2) Restore local files

```sh
tar xzf backup-YYYY-MM-DD-HHMMSS/stack-files.tar.gz
```

### 3) Create the Docker volumes

```sh
docker volume create docker-zitadel_data
docker volume create docker-zitadel_letsencrypt
```

### 4) Restore the PostgreSQL data volume

```sh
docker run --rm \
  -v docker-zitadel_data:/target \
  -v "$PWD/backup-YYYY-MM-DD-HHMMSS:/backup" \
  alpine sh -c 'cd /target && tar xzf /backup/docker-zitadel_data.tar.gz'
```

### 5) Restore the Let's Encrypt volume

```sh
docker run --rm \
  -v docker-zitadel_letsencrypt:/target \
  -v "$PWD/backup-YYYY-MM-DD-HHMMSS:/backup" \
  alpine sh -c 'cd /target && tar xzf /backup/docker-zitadel_letsencrypt.tar.gz'
```

### 6) Start the stack

```sh
docker compose up -d
```

### 7) Verify

```sh
docker compose ps
docker compose logs --tail=100 zitadel
```

---

## Notes

- For this stack, the most important data is the PostgreSQL volume and `.env`.
- Without the `letsencrypt` volume, Traefik can issue certificates again, but there may be a delay or ACME rate-limit risk.
- `login-client.pat` can usually be recreated, but restoring it avoids re-initialization work.
- If the target server uses a different folder name, Docker Compose may choose a different project name and different volume names. In that case, either use the same folder name or set `COMPOSE_PROJECT_NAME=docker-zitadel`.
