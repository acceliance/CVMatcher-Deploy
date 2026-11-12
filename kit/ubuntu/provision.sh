#!/usr/bin/env bash
# Provisioning complet de l'hôte : enchaîne les étapes 00 à 09 (idempotentes).
. "$(dirname "$0")/lib.sh"
require_root
cd "$(dirname "$0")"
for step in 00-preflight 01-system-update 02-firewall 03-docker 04-apache 05-letsencrypt 06-cockpit 07-backup 08-stage-app 09-apache-finalize; do
  log "étape $step"
  bash "./$step.sh"
done
log "provisioning terminé"
