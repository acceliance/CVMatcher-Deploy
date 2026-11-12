#!/usr/bin/env bash
# Installe la sauvegarde nocturne (timer systemd) : dump Neo4j à froid, volumes applicatifs, copie externe.
. "$(dirname "$0")/lib.sh"
require_root
load_config
install -m 0750 "$(dirname "$0")/backup-run.sh" /usr/local/sbin/cvmatcher-backup
install -m 0750 "$(dirname "$0")/restore-run.sh" /usr/local/sbin/cvmatcher-restore
cat > /etc/systemd/system/cvmatcher-backup.service <<EOF
[Unit]
Description=Sauvegarde CVMatcher (dump Neo4j à froid, fichiers, copie externe)
After=docker.service
[Service]
Type=oneshot
Environment=APP_DIR=${APP_DIR}
ExecStart=/usr/local/sbin/cvmatcher-backup
EOF
cat > /etc/systemd/system/cvmatcher-backup.timer <<EOF
[Unit]
Description=Sauvegarde nocturne CVMatcher
[Timer]
OnCalendar=*-*-* ${BACKUP_TIME:-02:30}:00
RandomizedDelaySec=300
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now cvmatcher-backup.timer
systemctl list-timers cvmatcher-backup.timer --no-pager
