#!/usr/bin/env bash
# Démarre ou met à jour l'application : pull (images publiques Docker Hub, sans login), up -d, attente de santé.
# Usage : deploy-app.sh [profils séparés par des virgules]
. "$(dirname "$0")/lib.sh"
require_root
cd "$APP_DIR"
set -a; . ./.env; set +a
args=()
for p in $(echo "${1:-${COMPOSE_PROFILES:-}}" | tr ',' ' '); do args+=(--profile "$p"); done
docker compose "${args[@]}" pull
docker compose "${args[@]}" up -d --remove-orphans
for i in $(seq 1 60); do
  if health=$(curl -fsS http://127.0.0.1:8090/api/health); then log "application saine (tag $TAG) : $health"; exit 0; fi
  sleep 5
done
docker compose ps
die "l'application n'est pas saine après 5 minutes"
