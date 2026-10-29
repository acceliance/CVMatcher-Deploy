#!/usr/bin/env bash
# Démarre ou met à jour l'application : login Harbor (robot deploy-pull), pull, up -d, attente de santé.
# Le mot de passe du robot arrive par l'entrée standard (jamais en argument ni dans les journaux).
# Usage : echo "$HARBOR_PULL_SECRET" | deploy-app.sh [profils séparés par des virgules]
. "$(dirname "$0")/lib.sh"
require_root
cd "$APP_DIR"
set -a; . ./.env; set +a
: "${HARBOR_PULL_USER:?HARBOR_PULL_USER manquant dans .env}"
[ "${TAG}" != "latest" ] || die "tag « latest » refusé en production"
docker login "${CVMATCHER_IMAGE_PREFIX%%/*}" -u "$HARBOR_PULL_USER" --password-stdin >/dev/null
args=()
for p in $(echo "${1:-${COMPOSE_PROFILES:-}}" | tr ',' ' '); do args+=(--profile "$p"); done
docker compose "${args[@]}" pull
docker compose "${args[@]}" up -d --remove-orphans
for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8090/api/health >/dev/null; then log "application saine (tag $TAG)"; exit 0; fi
  sleep 5
done
docker compose ps
die "l'application n'est pas saine après 5 minutes"
