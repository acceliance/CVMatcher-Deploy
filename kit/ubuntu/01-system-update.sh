#!/usr/bin/env bash
# Mise à jour du système et mises à jour de sécurité automatiques.
. "$(dirname "$0")/lib.sh"
require_root
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get -y -q upgrade
apt-get -y -q install ca-certificates curl gnupg jq unattended-upgrades ufw apache2 certbot python3-certbot-apache rsync
dpkg-reconfigure -f noninteractive unattended-upgrades
# SSH : clés uniquement, root désactivé (§7)
sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication no/; s/^#?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl reload ssh || systemctl reload sshd || true
log "système à jour"
