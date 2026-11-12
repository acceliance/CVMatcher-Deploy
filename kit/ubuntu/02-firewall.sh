#!/usr/bin/env bash
# Pare-feu ufw : SSH depuis ADMIN_IP seulement ; 80/443 depuis CUSTOMER_IPS (ou tout le monde si vide).
. "$(dirname "$0")/lib.sh"
require_root
load_config

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
for ip in $(echo "$ADMIN_IP" | tr ',' ' '); do ufw allow from "$ip" to any port 22 proto tcp; done
if [ -n "${CUSTOMER_IPS:-}" ]; then
  for ip in $(echo "$CUSTOMER_IPS" | tr ',' ' '); do
    ufw allow from "$ip" to any port 443 proto tcp
    ufw allow from "$ip" to any port 80 proto tcp
  done
  # Let's Encrypt (HTTP-01) doit joindre le port 80 depuis Internet
  warn "CUSTOMER_IPS restreint le port 80 : renouvellement Let's Encrypt par DNS-01 ou ouverture temporaire"
else
  ufw allow 80/tcp
  ufw allow 443/tcp
fi
ufw --force enable
ufw status verbose
