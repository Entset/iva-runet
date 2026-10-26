#!/bin/bash
# Сервер (VPS), транспорт WireGuard: домашний роутер/компьютер сам подключается к VPS.
# Запуск: sudo bash install-wireguard.sh            — поднять wg0, напечатать ключ сервера
#         sudo bash install-wireguard.sh <HOME_PUB> — то же и сразу добавить дом (или добавить позже: add-peer.sh)
# Ничего существующего не удаляет. RU-маршруты НЕ включает — это enable-routes.sh, когда дом подключился.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "нужен root: sudo bash $0"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
HOME_PUB=${1:-}
PORT=${PORT:-51820}
WAN=${WAN:-$(ip -4 route show default | awk '{print $5; exit}')}

echo "== 0: проверки"
[ -n "$WAN" ] || { echo "не нашёл внешний интерфейс (ip route show default) — задай WAN=eth0"; exit 1; }
echo "внешний интерфейс: $WAN, порт UDP $PORT"
ss -Hlun "sport = :$PORT" | grep -q . && { echo "порт $PORT занят — стоп (другой PORT=...)"; exit 1; }
[ -e /etc/wireguard/wg0.conf ] && { echo "/etc/wireguard/wg0.conf уже есть — стоп, не перезаписываю"; exit 1; }
ip rule show | grep -qE '^(100|101|102):' && { echo "ip rule с приоритетом 100–102 уже заняты — посмотри ip rule show"; exit 1; }

echo "== 1: пакеты и ключ"
command -v wg >/dev/null || { apt-get update -qq && apt-get install -y -qq wireguard-tools; }
umask 077
mkdir -p /etc/wireguard /etc/iva
cd /etc/wireguard
# Восстановление: положи старый server.key сюда заранее — дома ничего менять не придётся.
[ -s server.key ] || wg genkey > server.key
wg pubkey < server.key > server.pub

echo "== 2: wg0"
# Table=off: wg-quick маршрутов не ставит, RU-префиксы живут в таблице 100 (iva-ru-routes.sh).
# FwMark: собственные пакеты WireGuard не попадают в таблицу 100 (иначе петля).
cat > wg0.conf <<EOF
[Interface]
Address = 10.77.0.1/24
ListenPort = $PORT
MTU = 1380
Table = off
FwMark = 0xca6c
PrivateKey = $(cat server.key)
PostUp = ip rule add pref 100 fwmark 0xca6c lookup main
PreDown = ip rule del pref 100 fwmark 0xca6c lookup main
EOF
[ -n "$HOME_PUB" ] && printf '\n[Peer]\nPublicKey = %s\nAllowedIPs = 0.0.0.0/0\n' "$HOME_PUB" >> wg0.conf
chmod 600 wg0.conf
printf 'TRANSPORT=wg\nIFACE=wg0\nWAN=%s\n' "$WAN" > /etc/iva/tunnel.env
# ponytail: порт открыт всем — WireGuard без ключа молчит; сузить до дома нельзя, IP дома динамический
command -v ufw >/dev/null && ufw status | grep -q '^Status: active' && ufw allow "$PORT"/udp comment iva-wg0
systemctl enable --now wg-quick@wg0

"$HERE/install-routes-timer.sh"

echo "== проверки"
systemctl is-active wg-quick@wg0
wg show wg0 | grep -v 'private key'
echo
echo "ГОТОВО. Для настройки дома нужны:"
echo "  SERVER_PUB = $(cat /etc/wireguard/server.pub)"
echo "  VPS_IP     = $(curl -s --max-time 10 https://ifconfig.me/ip || echo '<внешний IP VPS>')"
echo "  PORT       = $PORT"
echo "Если у хостера есть свой файрвол (панель провайдера) — открой там UDP $PORT."
[ -n "$HOME_PUB" ] || echo "Когда дом выдаст свой публичный ключ: sudo bash $HERE/add-peer.sh <HOME_PUB>"
