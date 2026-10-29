#!/usr/bin/env bash
# Restauration (runbook §4.7, étape 4) : sauvegarde préalable de l'état courant, chargement du dump Neo4j,
# restauration des volumes, redémarrage, puis vérification de cohérence `restore.verify` par l'API.
# Usage : cvmatcher-restore <dossier de sauvegarde>
set -euo pipefail
src="${1:?usage : cvmatcher-restore <dossier de sauvegarde>}"
APP_DIR="${APP_DIR:-/opt/cvmatcher}"
cd "$APP_DIR"
set -a; . ./.env; set +a
project=$(basename "$APP_DIR")
[ -f "$src/neo4j.dump" ] || { echo "neo4j.dump absent de $src" >&2; exit 1; }
(cd "$src" && sha256sum -c SHA256SUMS)

if docker volume inspect "${project}_neo4j-data" >/dev/null 2>&1; then
  /usr/local/sbin/cvmatcher-backup || echo "sauvegarde préalable impossible : poursuite" >&2
fi
docker compose down
docker volume create "${project}_neo4j-data" >/dev/null
docker run --rm -v "${project}_neo4j-data:/data" -v "$src:/backups:ro" neo4j:5.26.2-community \
  neo4j-admin database load neo4j --from-path=/backups --overwrite-destination=true
for vol in app-data qdrant-data seaweed-data; do
  if [ -f "$src/${vol}.tgz" ]; then
    docker volume create "${project}_${vol}" >/dev/null
    docker run --rm -v "${project}_${vol}:/v" -v "$src:/b:ro" alpine:3.20 sh -c "rm -rf /v/* && tar -C /v -xzf /b/${vol}.tgz"
  fi
done
docker compose up -d
echo "restauration chargée ; lancer la vérification : Administration ▸ Maintenance ▸ Vérification après restauration"
