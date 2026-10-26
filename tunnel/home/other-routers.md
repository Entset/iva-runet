# Дом: Keenetic, MikroTik и другие роутеры

Роутер подходит как домашний выход, если он умеет **две вещи**: WireGuard-подключение к серверу
и NAT для трафика из этого подключения в интернет. Если чего-то нет — не мучай роутер,
возьми [linux.md](linux.md) (любой домашний Linux) или [ssh-any-device.md](ssh-any-device.md) / [android.md](android.md).

| Роутер | Подходит? | Как |
|---|---|---|
| OpenWrt (в т.ч. GL.iNet, Cudy, Xiaomi с прошивкой) | да, проверено | [openwrt.md](openwrt.md) |
| Keenetic (KeeneticOS 3.7+) | да, по документации | ниже |
| MikroTik (RouterOS 7) | да, по документации | ниже |
| ASUS на Asuswrt-Merlin | возможно (WireGuard client + свои iptables-скрипты) | лучше linux.md / ssh |
| ASUS/TP-Link/Xiaomi/Huawei на стоковой прошивке, роутер провайдера | нет: WireGuard-клиент у них только «весь дом в VPN» | linux.md / ssh / android |

Разделы ниже **не проверены на живом устройстве** — собраны по документации производителей.
Если что-то не совпадает в интерфейсе, покажи агенту экран/вывод и правь по месту.

Нужны с сервера: `SERVER_PUB`, `VPS_IP`, `PORT` (печатает `install-wireguard.sh`).

## Keenetic

1. Веб-интерфейс → «Параметры системы» → «Изменить набор компонентов» → включить **WireGuard VPN**, обновить.
2. Ключ: «Интернет» → «Другие подключения» → WireGuard → «Добавить подключение» → «Сгенерировать пару ключей»
   (публичный ключ — это `HOME_PUB`). Заполни: адрес `10.77.0.2/24`, MTU `1380`; пир — публичный ключ `<SERVER_PUB>`,
   адрес `<VPS_IP>:51820`, разрешённые подсети `10.77.0.1/32`, проверка активности 25 с.
   Либо импорт файла `iva.conf` (ключ тогда сгенерируй на любом компьютере: `wg genkey | tee key | wg pubkey`):

   ```ini
   [Interface]
   PrivateKey = <HOME_PRIV>
   Address = 10.77.0.2/24
   MTU = 1380

   [Peer]
   PublicKey = <SERVER_PUB>
   Endpoint = <VPS_IP>:51820
   AllowedIPs = 10.77.0.1/32
   PersistentKeepalive = 25
   ```
3. Галку **«Использовать для выхода в интернет» НЕ ставить** (иначе весь дом пойдёт в VPS).
4. Разрешить NAT для трафика из туннеля — в командной строке (веб: `http://192.168.1.1/a` или SSH/Telnet):
   ```
   interface Wireguard0 security-level public
   ip nat Wireguard0
   system configuration save
   ```
   (`Wireguard0` — имя интерфейса, если WireGuard-подключений несколько, посмотри `show interface`.)
   `security-level public` — туннель считается внешней сетью: в домашнюю сеть и в админку из него не пускает.
   Если с `public` трафик в интернет не пошёл — `security-level private` и запрет доступа из `Wireguard0` в домашнюю
   сеть правилом межсетевого экрана (иначе VPS увидит домашние устройства).
5. Публичный ключ роутера (`HOME_PUB`) — в карточке подключения; на сервере `sudo bash add-peer.sh <HOME_PUB>`.

Если на Keenetic уже настроен свой VPN «для выхода в интернет» — трафик Ивы уйдёт в него.
Тогда в «Приоритеты подключений» оставь основным провайдера, а VPN включай политиками только для своих устройств.

## MikroTik (RouterOS 7)

```
/interface wireguard add name=wg-iva mtu=1380 comment=iva
/interface wireguard peers add interface=wg-iva public-key="<SERVER_PUB>" endpoint-address=<VPS_IP> \
    endpoint-port=51820 allowed-address=10.77.0.1/32 persistent-keepalive=25s comment=iva
/ip address add address=10.77.0.2/24 interface=wg-iva comment=iva
/ip firewall nat add chain=srcnat src-address=10.77.0.0/24 out-interface-list=WAN action=masquerade comment=iva
/ip firewall filter add chain=forward in-interface=wg-iva out-interface-list=WAN action=accept comment=iva place-before=0
/ip firewall filter add chain=forward in-interface=wg-iva action=drop comment=iva place-before=1
/ip firewall filter add chain=input in-interface=wg-iva action=drop comment=iva place-before=0
/interface wireguard print      # public-key — это HOME_PUB
```

Проверка: `/interface wireguard peers print detail` → `last-handshake`. Откат: удалить всё с `comment=iva`.
