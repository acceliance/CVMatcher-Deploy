#!/usr/bin/env bash
# Durcissement final d'Apache : HSTS, en-têtes de proxy HTTPS ; la CSP reste celle de l'edge (une seule CSP).
. "$(dirname "$0")/lib.sh"
require_root
load_config
conf=/etc/apache2/sites-available/cvmatcher-le-ssl.conf
[ -f "$conf" ] || die "$conf absent : lancer 05-letsencrypt.sh"
if ! grep -q "Strict-Transport-Security" "$conf"; then
  sed -i "s#</VirtualHost>#    Header always set Strict-Transport-Security \"max-age=31536000; includeSubDomains\"\n    RequestHeader set X-Forwarded-Proto \"https\"\n</VirtualHost>#" "$conf"
fi
echo "ServerTokens Prod" > /etc/apache2/conf-available/cvmatcher-hardening.conf
echo "ServerSignature Off" >> /etc/apache2/conf-available/cvmatcher-hardening.conf
a2enconf cvmatcher-hardening >/dev/null
apachectl configtest
systemctl reload apache2
log "Apache finalisé (HSTS)"
