#!/bin/bash
# Общая часть обоих транспортов: скрипт маршрутов, сервис и таймер (таймер НЕ включается — это enable-routes.sh).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "нужен root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
echo "== маршруты: скрипт, сервис, таймер (пока выключен)"
install -m 755 "$HERE/iva-ru-routes.sh" /usr/local/bin/iva-ru-routes.sh
cat > /etc/systemd/system/iva-ru-routes.service <<'EOF'
[Unit]
Description=Iva: маршруты российских префиксов через домашний выход
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/iva-ru-routes.sh
EOF
cat > /etc/systemd/system/iva-ru-routes.timer <<'EOF'
[Unit]
Description=Iva: проверка домашнего выхода и RU-маршрутов каждые 5 минут

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
