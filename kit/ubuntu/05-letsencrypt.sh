#!/usr/bin/env bash
# Certificat Let's Encrypt et renouvellement automatique (timer systemd fourni par certbot).
. "$(dirname "$0")/lib.sh"
require_root
load_config
certbot --apache --non-interactive --agree-tos --redirect -m "$LETSENCRYPT_EMAIL" -d "$DOMAIN"
systemctl enable --now certbot.timer
certbot renew --dry-run
