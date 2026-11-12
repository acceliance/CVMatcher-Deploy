#!/usr/bin/env bash
# Certificat Let's Encrypt et renouvellement automatique (timer systemd fourni par certbot).
. "$(dirname "$0")/lib.sh"
require_root
load_config
certbot --apache --non-interactive --agree-tos --redirect -m "$LETSENCRYPT_EMAIL" -d "$DOMAIN"
# certificat préexistant obtenu autrement (ex. standalone pour Cockpit) : Apache occupe désormais le port 80,
# le renouvellement doit passer par Apache ; les autres paramètres (renew_hook de Cockpit) sont conservés
renewal="/etc/letsencrypt/renewal/$DOMAIN.conf"
if [ -f "$renewal" ] && ! grep -Eq '^authenticator *= *apache' "$renewal"; then
  log "renouvellement de $DOMAIN reconfiguré vers Apache"
  certbot reconfigure --cert-name "$DOMAIN" --apache --non-interactive
fi
systemctl enable --now certbot.timer
certbot renew --dry-run
