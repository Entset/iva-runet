# Дом: Linux-компьютер, который всегда включён (WireGuard)

Подходит, если роутер обычный (провайдерский, TP-Link, Xiaomi, ASUS на стоковой прошивке и т.п.),
а дома есть что-то на Linux, работающее 24/7: Raspberry Pi, мини-ПК, старый ноутбук, NAS с Docker/SSH,
домашний сервер. Роутер не трогаем вообще: компьютер сам подключается к VPS (серый IP не мешает).

Нужны с сервера: `SERVER_PUB`, `VPS_IP`, `PORT` (печатает `install-wireguard.sh`).
Не подходит для Windows/macOS — для них проще [ssh-any-device.md](ssh-any-device.md).

## 1. Пакеты и ключ

```bash
sudo apt install -y wireguard-tools iptables      # Debian/Ubuntu/Raspberry Pi OS
umask 077; wg genkey | sudo tee /etc/wireguard/wgiva.key | wg pubkey   # ← HOME_PUB, отдать на сервер (add-peer.sh)
ip -4 route show default                           # имя интерфейса в интернет: eth0 / enp3s0 / wlan0
```

## 2. Конфиг `/etc/wireguard/wgiva.conf`

Подставь `<LAN_IF>` (интерфейс из шага 1), `<SERVER_PUB>`, `<VPS_IP>`.

```ini
[Interface]
Address = 10.77.0.2/24
MTU = 1380
# Table=off: компьютер сам ничего в туннель не отправляет, его интернет не меняется
Table = off
PostUp = wg set %i private-key /etc/wireguard/wgiva.key
PostUp = sysctl -qw net.ipv4.ip_forward=1
PostUp = iptables -t nat -A POSTROUTING -s 10.77.0.0/24 -o <LAN_IF> -j MASQUERADE -m comment --comment iva
PostUp = iptables -I FORWARD -i %i -o <LAN_IF> -j ACCEPT -m comment --comment iva
PostUp = iptables -I FORWARD -i <LAN_IF> -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment iva
# из туннеля — только в интернет: не пускаем в домашнюю сеть
PostUp = iptables -I FORWARD -i %i -d 192.168.0.0/16,10.0.0.0/8,172.16.0.0/12 -j DROP -m comment --comment iva
PostUp = iptables -I INPUT -i %i -j DROP -m comment --comment iva
PostDown = iptables -t nat -D POSTROUTING -s 10.77.0.0/24 -o <LAN_IF> -j MASQUERADE -m comment --comment iva
PostDown = iptables -D FORWARD -i %i -o <LAN_IF> -j ACCEPT -m comment --comment iva
PostDown = iptables -D FORWARD -i <LAN_IF> -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment iva
PostDown = iptables -D FORWARD -i %i -d 192.168.0.0/16,10.0.0.0/8,172.16.0.0/12 -j DROP -m comment --comment iva
PostDown = iptables -D INPUT -i %i -j DROP -m comment --comment iva

[Peer]
PublicKey = <SERVER_PUB>
Endpoint = <VPS_IP>:51820
AllowedIPs = 10.77.0.1/32
PersistentKeepalive = 25
```

Приватный ключ не в конфиге, а в `wgiva.key` (подставляется в `PostUp`) — конфиг можно показывать агенту.
`sudo chmod 600 /etc/wireguard/wgiva.conf`.

Порядок правил: `-I` ставит каждое следующее выше предыдущего, поэтому DROP в домашнюю сеть
оказывается первым — до разрешающего правила.

## 3. Запуск и автозапуск

```bash
sudo systemctl enable --now wg-quick@wgiva
sudo wg show wgiva            # latest handshake (после add-peer.sh на сервере)
ping -c2 10.77.0.1
```

## Если на этом компьютере уже включён VPN по умолчанию

Тогда интернет для Ивы пойдёт через тот VPN, а не через домашний IP. Выпусти трафик туннеля мимо него:

```bash
GW=$(ip -4 route show default table main | awk '/via/ {print $3; exit}')   # шлюз домашнего роутера
sudo ip route replace default via "$GW" dev <LAN_IF> table 200
sudo ip route replace 10.77.0.0/24 dev wgiva table 200
sudo ip rule add from 10.77.0.0/24 lookup 200 priority 100
```

(чтобы пережило перезагрузку — добавь эти строки как `PostUp` в `wgiva.conf`).

## Docker на этом компьютере

Docker ставит `FORWARD DROP` — правила выше вставлены через `-I` и стоят выше, ничего дополнительно не нужно.

## Откат

```bash
sudo systemctl disable --now wg-quick@wgiva
sudo rm /etc/wireguard/wgiva.conf /etc/wireguard/wgiva.key
```
