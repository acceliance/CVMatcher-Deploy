#!/usr/bin/env bash
# Apache en reverse proxy vers l'edge (127.0.0.1:8090). TLS posé par 05 ; HSTS ajouté par 09.
. "$(dirname "$0")/lib.sh"
require_root
load_config
a2enmod proxy proxy_http headers ssl rewrite >/dev/null
TIMEOUT=$(( ${A2A_TASK_TIMEOUT:-240} + 60 ))
cat > /etc/apache2/sites-available/cvmatcher.conf <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ProxyPreserveHost On
    ProxyTimeout ${TIMEOUT}
    # réponses en flux du transport MCP (streamable HTTP, §3.2)
    ProxyPass        /api/mcp http://127.0.0.1:8090/api/mcp flushpackets=on
    ProxyPassReverse /api/mcp http://127.0.0.1:8090/api/mcp
    ProxyPass        / http://127.0.0.1:8090/
    ProxyPassReverse / http://127.0.0.1:8090/
    RequestHeader set X-Forwarded-Proto "http"
</VirtualHost>
EOF
a2dissite 000-default >/dev/null 2>&1 || true
a2ensite cvmatcher >/dev/null
apachectl configtest
systemctl reload apache2
