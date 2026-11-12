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
# Swap de sécurité (§8) : amortit les pics mémoire (Neo4j + OCR) au lieu de laisser l'OOM killer tuer un conteneur.
# Créé seulement si l'hôte n'a aucun swap ; swappiness basse pour ne swapper qu'en dernier recours.
if [ -z "$(swapon --noheadings --show)" ]; then
  fallocate -l "${SWAP_SIZE:-4G}" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  log "swap de ${SWAP_SIZE:-4G} créé"
fi
echo 'vm.swappiness=10' > /etc/sysctl.d/99-cvmatcher-swap.conf
sysctl -q -p /etc/sysctl.d/99-cvmatcher-swap.conf
log "système à jour"
