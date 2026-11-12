#!/usr/bin/env bash
# Fonctions communes du provisioning (sourcé par chaque étape). Lit /opt/cvmatcher-kit/config.env.
set -euo pipefail

KIT_DIR="${KIT_DIR:-/opt/cvmatcher-kit}"
APP_DIR="${APP_DIR:-/opt/cvmatcher}"
CONFIG="${CONFIG:-$KIT_DIR/config.env}"

log()  { printf '\033[1;34m[cvmatcher]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[avertissement]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[erreur]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() { [ "$(id -u)" -eq 0 ] || die "à lancer en root (sudo)"; }

load_config() {
  [ -f "$CONFIG" ] || die "configuration absente : $CONFIG"
  if grep -q $'\r' "$CONFIG"; then die "$CONFIG est en fins de ligne CRLF"; fi
  set -a
  # shellcheck disable=SC1090
  . "$CONFIG"
  set +a
  : "${DOMAIN:?DOMAIN manquant dans config.env}"
  : "${ADMIN_IP:?ADMIN_IP manquant dans config.env}"
  : "${LETSENCRYPT_EMAIL:?LETSENCRYPT_EMAIL manquant dans config.env}"
}
