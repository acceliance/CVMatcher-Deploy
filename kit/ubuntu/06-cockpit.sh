#!/usr/bin/env bash
# Cockpit (optionnel, INSTALL_COCKPIT=true) : console web d'administration, restreinte à ADMIN_IP.
. "$(dirname "$0")/lib.sh"
require_root
load_config
if [ "${INSTALL_COCKPIT:-false}" != "true" ]; then log "Cockpit non demandé"; exit 0; fi
apt-get -y -q install cockpit
for ip in $(echo "$ADMIN_IP" | tr ',' ' '); do ufw allow from "$ip" to any port 9090 proto tcp; done
systemctl enable --now cockpit.socket
log "Cockpit sur le port 9090, depuis $ADMIN_IP seulement"
