#!/bin/bash
# Включить RU-маршруты через домашний выход: проверки до/после, таймер каждые 5 мин. Запуск: sudo bash enable-routes.sh
# Откат одной строкой: sudo systemctl disable --now iva-ru-routes.timer; sudo ip route flush table 100
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "нужен root: sudo bash $0"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. /etc/iva/tunnel.env

check() {
  echo "-- маршрут до 77.88.8.8 (Яндекс DNS, RU): $(ip route get 77.88.8.8 | head -1)"
  echo "-- маршрут до 1.1.1.1 (не RU):            $(ip route get 1.1.1.1 | head -1)"
  echo "-- IP для обычных сайтов (ifconfig.me):    $(curl -s --max-time 10 https://ifconfig.me/ip)"
  echo "-- IP для российских сайтов (Яндекс):       $(curl -4 -s --max-time 15 https://ipv4-internet.yandex.net/api/v0/ip)"
  for u in https://www.gosuslugi.ru https://ya.ru https://www.avito.ru; do
    echo "-- $u: $(curl -s -o /dev/null --max-time 20 -w '%{http_code} %{time_total}s' "$u")"
  done
}

echo "== до (оба IP одинаковые — IP VPS)"
check

echo "== включаем маршруты ($TRANSPORT через $IFACE)"
install -m 755 "$HERE/iva-ru-routes.sh" /usr/local/bin/iva-ru-routes.sh
systemctl start iva-ru-routes.service || { journalctl -u iva-ru-routes.service -n 20 --no-pager; exit 1; }
journalctl -u iva-ru-routes.service -n 3 --no-pager -o cat

echo "== после: ifconfig.me = IP VPS, ipv4-internet.yandex.net = домашний (или мобильный) IP"
check
systemctl enable --now iva-ru-routes.timer
systemctl list-timers iva-ru-routes.timer --no-pager
echo "ГОТОВО. Если эта SSH-сессия жива — ответы на входящие соединения идут как раньше."
