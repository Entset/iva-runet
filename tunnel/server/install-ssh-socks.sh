#!/bin/bash
# Сервер (VPS), транспорт SSH: телефон или любой домашний компьютер держит `ssh -R 1080` к VPS,
# получается SOCKS-прокси, который выходит в интернет из дома. tun2socks превращает его в интерфейс ivasocks,
# дальше всё как у WireGuard: RU-префиксы в таблице 100 → ivasocks.
# Без root, без роутера, без белого IP дома. Только TCP (UDP/QUIC к RU-сайтам не ходит, браузер сам откатывается на TCP).
# Запуск: sudo bash install-ssh-socks.sh            — пользователь ivatun, tun2socks, сервис
#         sudo bash add-device.sh "<ssh-ed25519 ...>" — пустить устройство (ключ с телефона/компьютера)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "нужен root: sudo bash $0"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
SOCKS_PORT=${SOCKS_PORT:-1080}
TUN2SOCKS_VER=${TUN2SOCKS_VER:-v2.5.2}
WAN=${WAN:-$(ip -4 route show default | awk '{print $5; exit}')}

echo "== 0: проверки"
[ -e /etc/iva/tunnel.env ] && ! grep -q TRANSPORT=socks /etc/iva/tunnel.env && { echo "уже стоит другой транспорт: $(cat /etc/iva/tunnel.env) — сначала его откат"; exit 1; }
ss -Htln "sport = :$SOCKS_PORT" | grep -q . && { echo "порт $SOCKS_PORT уже слушается — стоп (другой SOCKS_PORT=...)"; exit 1; }
ip rule show | grep -qE '^(101|102):' && ! grep -q TRANSPORT=socks /etc/iva/tunnel.env 2>/dev/null && { echo "ip rule 101/102 заняты — посмотри ip rule show"; exit 1; }
sshd -T 2>/dev/null | grep -qiE '^allowtcpforwarding (no|local)' && { echo "в sshd_config AllowTcpForwarding запрещает -R. Нужно yes или remote (можно Match User ivatun)."; exit 1; }
if sshd -T 2>/dev/null | grep -qi '^allowusers'; then
  echo "ВНИМАНИЕ: в sshd_config есть AllowUsers — добавь туда ivatun, иначе устройство не войдёт."
fi

echo "== 1: пользователь ivatun (только проброс порта, без шелла)"
id ivatun >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin ivatun
install -d -m 700 -o ivatun -g ivatun ~ivatun/.ssh
touch ~ivatun/.ssh/authorized_keys; chown ivatun:ivatun ~ivatun/.ssh/authorized_keys; chmod 600 ~ivatun/.ssh/authorized_keys

echo "== 2: tun2socks $TUN2SOCKS_VER"
if ! command -v tun2socks >/dev/null; then
  case $(uname -m) in x86_64) A=amd64 ;; aarch64) A=arm64 ;; *) echo "архитектура $(uname -m): положи бинарь tun2socks в /usr/local/bin сам"; exit 1 ;; esac
  command -v unzip >/dev/null || apt-get install -y -qq unzip
  T=$(mktemp -d)
  curl -fsSL -o "$T/t.zip" "https://github.com/xjasonlyu/tun2socks/releases/download/$TUN2SOCKS_VER/tun2socks-linux-$A.zip"
  echo "sha256 архива: $(sha256sum "$T/t.zip" | cut -d' ' -f1) (сверь со страницей релиза, если важно)"
  unzip -q -o "$T/t.zip" -d "$T" && install -m 755 "$T/tun2socks-linux-$A" /usr/local/bin/tun2socks
  rm -rf "$T"
fi
tun2socks -version | head -1

echo "== 3: сервис iva-socks-tun"
mkdir -p /etc/iva
printf 'TRANSPORT=socks\nIFACE=ivasocks\nSOCKS_PORT=%s\nWAN=%s\n' "$SOCKS_PORT" "$WAN" > /etc/iva/tunnel.env
cat > /etc/systemd/system/iva-socks-tun.service <<EOF
[Unit]
Description=Iva: интерфейс ivasocks поверх SOCKS 127.0.0.1:$SOCKS_PORT (ssh -R с домашнего устройства)
After=network-online.target

[Service]
ExecStartPre=-ip link del ivasocks
ExecStartPre=ip tuntap add mode tun dev ivasocks
ExecStartPre=ip addr add 198.18.0.1/30 dev ivasocks
ExecStartPre=ip link set dev ivasocks up
ExecStart=/usr/local/bin/tun2socks -device ivasocks -proxy socks5://127.0.0.1:$SOCKS_PORT -loglevel warning
ExecStopPost=-ip link del ivasocks
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now iva-socks-tun.service

"$HERE/install-routes-timer.sh"

echo
echo "ГОТОВО. Дальше:"
echo "  1. На устройстве создать ключ и прислать публичную часть (tunnel/home/ssh-any-device.md или android.md)."
echo "  2. sudo bash $HERE/add-device.sh \"<ssh-ed25519 AAAA... имя>\""
echo "  3. На устройстве запустить: ssh -N -R 127.0.0.1:$SOCKS_PORT ivatun@<VPS_IP>"
echo "  4. sudo bash $HERE/enable-routes.sh"
