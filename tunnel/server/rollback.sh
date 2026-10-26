#!/bin/bash
# Полный откат серверной части (любой транспорт). Запуск: sudo bash rollback.sh
# Ключ сервера /etc/wireguard/server.key НЕ удаляется — пригодится, чтобы не перенастраивать дом.
[ "$(id -u)" = 0 ] || { echo "нужен root"; exit 1; }
. /etc/iva/tunnel.env 2>/dev/null
WAN=${WAN:-$(ip -4 route show default | awk '{print $5; exit}')}
systemctl disable --now iva-ru-routes.timer iva-socks-tun.service 2>/dev/null
systemctl disable --now wg-quick@wg0 2>/dev/null
for v in 4 6; do
  ip -$v route flush table 100 2>/dev/null
  ip -$v rule del pref 102 lookup 100 2>/dev/null
  ip -$v rule del pref 101 fwmark 0x2000000/0x2000000 lookup main 2>/dev/null
  IPT=iptables; [ $v = 6 ] && IPT=ip6tables
  for R in "PREROUTING -i $WAN -m conntrack --ctstate NEW -j CONNMARK --set-xmark 0x2000000/0x2000000" \
           "PREROUTING -j CONNMARK --restore-mark --mask 0x2000000" "OUTPUT -j CONNMARK --restore-mark --mask 0x2000000"; do
    $IPT -t mangle -D $R -m comment --comment iva-ru 2>/dev/null
  done
done
command -v ufw >/dev/null && ufw delete allow 51820/udp 2>/dev/null
rm -f /etc/systemd/system/iva-ru-routes.{service,timer} /etc/systemd/system/iva-socks-tun.service /usr/local/bin/iva-ru-routes.sh
rm -rf /etc/iva
[ -f /etc/wireguard/wg0.conf ] && mv /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.off
systemctl daemon-reload
echo "откат готов. Пользователь ivatun (если был) оставлен: userdel -r ivatun"
ip rule show
