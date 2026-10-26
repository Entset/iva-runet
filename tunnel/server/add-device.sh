#!/bin/bash
# Пустить домашнее устройство по SSH. Запуск: sudo bash add-device.sh "<ssh-ed25519 AAAA... имя>"
# Нужен для SSH-транспорта (порт 1080).
# Ключу разрешено ровно одно: слушать этот порт на 127.0.0.1 VPS. Шелла, команд, пробросов внутрь — нет
# (проверено: restrict + permitlisten + command="/bin/false"; без command= restrict команды НЕ запрещает).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "нужен root"; exit 1; }
KEY=${1:?нужен публичный ключ устройства в кавычках}
[[ $KEY =~ ^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa)\ [A-Za-z0-9+/=]+ ]] || { echo "это не публичный ssh-ключ"; exit 1; }
. /etc/iva/tunnel.env 2>/dev/null || true
SOCKS_PORT=${SOCKS_PORT:-1080}
id ivatun >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin ivatun
install -d -m 700 -o ivatun -g ivatun ~ivatun/.ssh
AK=~ivatun/.ssh/authorized_keys
touch "$AK"; chown ivatun:ivatun "$AK"; chmod 600 "$AK"
sshd -T 2>/dev/null | grep -qi '^allowusers' && echo "ВНИМАНИЕ: в sshd_config есть AllowUsers — добавь туда ivatun."
B64=$(awk '{print $2}' <<<"$KEY")
grep -qF "$B64" "$AK" && { echo "ключ уже добавлен"; exit 0; }
echo "restrict,port-forwarding,permitlisten=\"127.0.0.1:$SOCKS_PORT\",command=\"/bin/false\" $KEY" >> "$AK"
VPS=$(curl -s --max-time 10 https://ifconfig.me/ip || echo '<VPS_IP>')
echo "OK. На устройстве:"
echo "  ssh -N -R 127.0.0.1:$SOCKS_PORT ivatun@$VPS"
echo "Отозвать: удалить строку с этим ключом из $AK"
