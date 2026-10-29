#!/usr/bin/env bash
# Installe le kit compose dans /opt/cvmatcher (compose + .env de l'instance ; .env en 0600).
. "$(dirname "$0")/lib.sh"
require_root
load_config
install -d -m 0750 "$APP_DIR" "$APP_DIR/secrets"
install -m 0640 "$KIT_DIR/compose/docker-compose.yaml" "$APP_DIR/docker-compose.yaml"
[ -f "$KIT_DIR/app.env" ] || die "$KIT_DIR/app.env absent (copié par deploy.ps1 -Stage config)"
if grep -q $'\r' "$KIT_DIR/app.env"; then die "app.env est en fins de ligne CRLF"; fi
install -m 0600 "$KIT_DIR/app.env" "$APP_DIR/.env"
if [ -f "$KIT_DIR/seaweedfs-s3.json" ]; then install -m 0600 "$KIT_DIR/seaweedfs-s3.json" "$APP_DIR/secrets/seaweedfs-s3.json"; fi
rm -f "$KIT_DIR/app.env" "$KIT_DIR/seaweedfs-s3.json"
log "kit installé dans $APP_DIR"
