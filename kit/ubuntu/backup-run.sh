#!/usr/bin/env bash
# Sauvegarde de l'instance (spec §4.3), lancée par le timer nocturne ou par scripts/backup-now.ps1.
#  1. arrêt de l'API et du worker (les tâches en cours sont remises en file au redémarrage) ;
#  2. dump Neo4j à froid (édition community : pas de sauvegarde à chaud) ;
#  3. archives des volumes app-data, et qdrant-data / seaweed-data si les profils sont actifs ;
#  4. redémarrage, rétention locale, copie externe chiffrée (obligatoire en production, K-12).
set -euo pipefail
APP_DIR="${APP_DIR:-/opt/cvmatcher}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/cvmatcher}"
cd "$APP_DIR"
set -a; . ./.env; set +a
stamp=$(date -u +%Y%m%dT%H%M%SZ)
dest="$BACKUP_DIR/$stamp"
mkdir -p "$dest"
chmod 0700 "$BACKUP_DIR"
project=$(basename "$APP_DIR")
profiles=$(docker compose ps --format '{{.Service}}' | tr '\n' ' ')

docker compose stop cvmatcher-worker cvmatcher-api
trap 'docker compose up -d cvmatcher-api cvmatcher-worker' EXIT
docker compose stop neo4j
docker run --rm -v "${project}_neo4j-data:/data" -v "$dest:/backups" neo4j:5.26.2-community \
  neo4j-admin database dump neo4j --to-path=/backups
for vol in app-data qdrant-data seaweed-data; do
  if docker volume inspect "${project}_${vol}" >/dev/null 2>&1; then
    case "$vol" in
      qdrant-data) [[ "$profiles" == *qdrant* ]] || continue ;;
      seaweed-data) [[ "$profiles" == *seaweedfs* ]] || continue ;;
    esac
    docker run --rm -v "${project}_${vol}:/v:ro" -v "$dest:/b" alpine:3.20 tar -C /v -czf "/b/${vol}.tgz" .
  fi
done
docker compose up -d neo4j
docker compose up -d cvmatcher-api cvmatcher-worker
trap - EXIT
(cd "$dest" && sha256sum ./* > SHA256SUMS)
echo "{\"tag\": \"${TAG}\", \"date\": \"$stamp\", \"fqdn\": \"${INSTANCE_FQDN}\"}" > "$dest/manifest.json"

# rétention locale
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+${BACKUP_RETENTION_DAYS:-14}" -exec rm -rf {} +

# copie externe chiffrée (age ou gpg) vers S3 ou rsync
if [ -n "${BACKUP_REMOTE:-}" ]; then
  archive="$BACKUP_DIR/cvmatcher-${INSTANCE_FQDN}-${stamp}.tar"
  tar -C "$BACKUP_DIR" -cf "$archive" "$stamp"
  if [ -n "${BACKUP_AGE_RECIPIENT:-}" ]; then
    age -r "$BACKUP_AGE_RECIPIENT" -o "$archive.age" "$archive" && rm -f "$archive" && archive="$archive.age"
  else
    echo "BACKUP_AGE_RECIPIENT absent : la copie externe doit être chiffrée" >&2; rm -f "$archive"; exit 2
  fi
  case "$BACKUP_REMOTE" in
    s3://*) aws s3 cp --only-show-errors "$archive" "$BACKUP_REMOTE/" ${BACKUP_S3_ENDPOINT:+--endpoint-url "$BACKUP_S3_ENDPOINT"} ;;
    *) rsync -a "$archive" "$BACKUP_REMOTE/" ;;
  esac
  rm -f "$archive"
elif [ "${ENVIRONMENT:-production}" = "production" ]; then
  echo "AVERTISSEMENT : aucune copie externe (BACKUP_REMOTE) en production" >&2
fi
echo "sauvegarde : $dest"
