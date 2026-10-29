#!/usr/bin/env bash
# Contrôles préalables : OS, ressources, DNS du FQDN vers cette VM.
. "$(dirname "$0")/lib.sh"
require_root
load_config

. /etc/os-release
case "$VERSION_ID" in 22.04|24.04) log "Ubuntu $VERSION_ID" ;; *) die "Ubuntu 22.04 ou 24.04 LTS attendu (trouvé : $PRETTY_NAME)" ;; esac

cpus=$(nproc)
mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
disk_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
log "ressources : ${cpus} vCPU, ${mem_gb} Go de RAM, ${disk_gb} Go libres"
[ "$cpus" -ge 4 ] || die "4 vCPU au minimum (§8)"
[ "$mem_gb" -ge 7 ] || die "8 Go de RAM au minimum (§8)"
[ "$disk_gb" -ge 60 ] || die "60 Go libres au minimum sur / (§8)"

public_ip=$(curl -fsS --max-time 10 https://api.ipify.org || true)
resolved=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1 {print $1}' || true)
if [ -z "$resolved" ]; then
  die "$DOMAIN ne se résout pas : créer l'enregistrement DNS avant le provisioning"
elif [ -n "$public_ip" ] && [ "$resolved" != "$public_ip" ]; then
  warn "$DOMAIN pointe vers $resolved, l'IP publique de cette VM est $public_ip (Let's Encrypt échouera)"
else
  log "DNS : $DOMAIN → $resolved"
fi
