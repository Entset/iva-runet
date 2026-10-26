#!/bin/bash
# Диагностика без изменений. Можно без root (часть строк тогда пустая).
. /etc/iva/tunnel.env 2>/dev/null || { echo "туннель не установлен (/etc/iva/tunnel.env нет)"; exit 1; }
echo "транспорт: $TRANSPORT, интерфейс: $IFACE"
if [ "$TRANSPORT" = wg ]; then
  echo "handshake: $(sudo -n wg show wg0 latest-handshakes 2>/dev/null | awk '{ if ($2>0) print systime()-$2 " с назад"; else print "не было" }')"
else
  echo "устройство на связи (порт ${SOCKS_PORT:-1080}): $(ss -Htln "sport = :${SOCKS_PORT:-1080}" | grep -q . && echo да || echo НЕТ)"
  echo "iva-socks-tun: $(systemctl is-active iva-socks-tun)"
fi
echo "таймер: $(systemctl is-active iva-ru-routes.timer)"
echo "RU-маршрутов в таблице 100: $(ip route show table 100 | wc -l) (0 = выход не работает, Ива ходит напрямую)"
echo "маршрут до ya.ru: $(ip route get 77.88.8.8 | head -1)"
echo "IP для обычных сайтов:    $(curl -s --max-time 10 https://ifconfig.me/ip)"
echo "IP для российских сайтов: $(curl -4 -s --max-time 15 https://ipv4-internet.yandex.net/api/v0/ip)"
journalctl -u iva-ru-routes.service -n 3 --no-pager -o cat 2>/dev/null
