# Дом: роутер на OpenWrt (WireGuard)

Проверено на живом роутере (OpenWrt, opkg и apk). Отличие от проверенного: зона файрвола B3 ужесточена
(`input`/`forward` = REJECT вместо ACCEPT) — туннелю это не мешает, он только выходит в интернет. Роутер сам подключается к VPS, поэтому
серый IP/CGNAT дома не мешает. Нужны с сервера: `SERVER_PUB`, `VPS_IP`, `PORT` (печатает `install-wireguard.sh`).

Вставлять в SSH-сессию роутера (`ssh root@192.168.1.1`) по блокам.

## B0. Диагностика — сначала это, вывод показать агенту

```sh
. /lib/functions/network.sh
network_get_device WDEV wan; network_get_gateway4 WGW wan
echo "WAN dev=$WDEV gw=$WGW"
ip -4 route show default
ip rule show
uci show network | grep -Ei 'proto=.?(wireguard|openvpn|sing|xray|amnezia)'
cat /etc/os-release | head -2
df -h /overlay | tail -1
```

Если в выводе есть свой VPN-клиент (wireguard/openvpn/amnezia/sing-box) и default route идёт через него —
обязателен блок B4, иначе трафик Ивы уйдёт в этот VPN, а не в домашний интернет.

## B1. Пакеты и ключ роутера

```sh
opkg update && opkg install wireguard-tools      # OpenWrt 25+: apk update && apk add wireguard-tools
umask 077; wg genkey | tee /etc/wgiva.key | wg pubkey   # ← это HOME_PUB, отдать на сервер (add-peer.sh)
```

## B2. Интерфейс туннеля

Адрес `/24` — чтобы ответы на 10.77.0.1 шли в wgiva. Пиру разрешён только 10.77.0.1/32,
`route_allowed_ips=0`: роутер ничего своего в туннель не отправляет.

```sh
uci set network.wgiva=interface
uci set network.wgiva.proto='wireguard'
uci set network.wgiva.private_key="$(cat /etc/wgiva.key)"
uci set network.wgiva.addresses='10.77.0.2/24'
uci set network.wgiva.mtu='1380'
uci set network.iva_peer='wireguard_wgiva'
uci set network.iva_peer.public_key='<SERVER_PUB>'
uci set network.iva_peer.allowed_ips='10.77.0.1/32'
uci set network.iva_peer.endpoint_host='<VPS_IP>'
uci set network.iva_peer.endpoint_port='51820'
uci set network.iva_peer.persistent_keepalive='25'
uci set network.iva_peer.route_allowed_ips='0'
uci commit network
/etc/init.d/network reload
sleep 8; wg show wgiva          # ждём "latest handshake" (после add-peer.sh на сервере)
```

## B3. Зона файрвола: из туннеля — только в интернет

```sh
uci set firewall.iva=zone
uci set firewall.iva.name='iva'
uci set firewall.iva.input='REJECT'
uci set firewall.iva.output='ACCEPT'
uci set firewall.iva.forward='REJECT'
uci set firewall.iva.masq='1'
uci set firewall.iva.mtu_fix='1'
uci add_list firewall.iva.network='wgiva'
uci set firewall.iva_wan=forwarding
uci set firewall.iva_wan.src='iva'
uci set firewall.iva_wan.dest='wan'
uci commit firewall
/etc/init.d/firewall reload
```

`input=REJECT` и нет форвардинга в `lan`: VPS не видит ни админку роутера, ни домашние устройства — только выход в интернет.

## B4. Только если на роутере уже есть свой VPN по умолчанию

Трафик туннеля Ивы выпускаем в WAN напрямую, мимо этого VPN (таблица 200):

```sh
cat >/etc/hotplug.d/iface/90-ivaroute <<'EOF'
#!/bin/sh
[ "$ACTION" = "ifup" ] || [ "$ACTION" = "ifupdate" ] || exit 0
case "$INTERFACE" in wgiva|wan) ;; *) exit 0 ;; esac
sleep 2
. /lib/functions/network.sh
network_get_device WDEV wan || exit 0
network_get_gateway4 WGW wan
[ -n "$WDEV" ] || exit 0
ip route replace 10.77.0.0/24 dev wgiva table 200
if [ -n "$WGW" ]; then ip route replace default via "$WGW" dev "$WDEV" table 200
else ip route replace default dev "$WDEV" table 200; fi
ip rule del from 10.77.0.0/24 lookup 200 2>/dev/null
ip rule del to 10.77.0.0/24 lookup 200 2>/dev/null
ip rule add from 10.77.0.0/24 lookup 200 priority 100
ip rule add to 10.77.0.0/24 lookup 200 priority 101
logger -t ivaroute "table 200: dev=$WDEV gw=$WGW"
EOF
chmod +x /etc/hotplug.d/iface/90-ivaroute
ACTION=ifup INTERFACE=wan sh /etc/hotplug.d/iface/90-ivaroute
echo /etc/hotplug.d/iface/90-ivaroute >> /etc/sysupgrade.conf
```

## Проверка

```sh
wg show wgiva                 # latest handshake < 2 мин
ping -c2 10.77.0.1            # VPS через туннель
```

## После обновления прошивки (sysupgrade)

`/etc/config` и `/etc/wgiva.key` сохраняются (добавь ключ: `echo /etc/wgiva.key >> /etc/sysupgrade.conf`).
Заново поставить `wireguard-tools` (B1, без генерации ключа).

## Откат

```sh
rm -f /etc/hotplug.d/iface/90-ivaroute /etc/wgiva.key
ip rule del from 10.77.0.0/24 lookup 200; ip rule del to 10.77.0.0/24 lookup 200; ip route flush table 200
uci delete network.iva_peer; uci delete network.wgiva; uci delete firewall.iva; uci delete firewall.iva_wan
uci commit; /etc/init.d/network reload; /etc/init.d/firewall reload
```
