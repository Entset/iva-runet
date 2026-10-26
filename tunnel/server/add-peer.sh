#!/bin/bash
# Добавить (или заменить) домашний конец WireGuard. Запуск: sudo bash add-peer.sh <HOME_PUB>
# Пир один: новый ключ заменяет старый (новый роутер, сброс, переезд с роутера на домашний компьютер).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "нужен root: sudo bash $0 <HOME_PUB>"; exit 1; }
PUB=${1:?нужен публичный ключ дома: sudo bash $0 <HOME_PUB>}
[[ $PUB =~ ^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$ ]] || { echo "это не похоже на ключ WireGuard: $PUB"; exit 1; }
CONF=/etc/wireguard/wg0.conf
cp -p "$CONF" "$CONF.bak"
# убрать прежний [Peer] целиком и дописать новый
awk '/^\[Peer\]/{skip=1} /^\[Interface\]/{skip=0} !skip && NF' "$CONF.bak" > "$CONF"
printf '\n[Peer]\nPublicKey = %s\nAllowedIPs = 0.0.0.0/0\n' "$PUB" >> "$CONF"
chmod 600 "$CONF"
systemctl restart wg-quick@wg0
echo "пир заменён (бэкап $CONF.bak). Ждём handshake от дома:"
for i in $(seq 1 12); do
  HS=$(wg show wg0 latest-handshakes | awk '{print $2}')
  [ "${HS:-0}" -gt 0 ] && { echo "OK: handshake есть. Дальше: sudo bash $(dirname "$0")/enable-routes.sh"; exit 0; }
  sleep 5
done
echo "handshake пока нет — проверь дом (ключ сервера, VPS_IP, порт) и файрвол хостера. Повторная проверка: sudo wg show wg0"
