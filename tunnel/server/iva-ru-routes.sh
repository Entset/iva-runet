#!/bin/bash
# Маршруты к российским префиксам через домашний выход (таблица 100).
# Таймер дёргает каждые 5 мин: выход упал — таблица чистится и Ива ходит напрямую; поднялся — маршруты возвращаются.
# Список префиксов качается не чаще раза в сутки.
# Настройки: /etc/iva/tunnel.env (пишут install-wireguard.sh / install-ssh-socks.sh):
#   TRANSPORT=wg|socks  IFACE=wg0|ivasocks  SOCKS_PORT=1080  WAN=<внешний интерфейс VPS, пусто = по default route>
set -uo pipefail
[ -f /etc/iva/tunnel.env ] && . /etc/iva/tunnel.env
TRANSPORT=${TRANSPORT:-wg}
IFACE=${IFACE:-wg0}
SOCKS_PORT=${SOCKS_PORT:-1080}
WAN=${WAN:-$(ip -4 route show default | awk '{print $5; exit}')}
TABLE=100
LIST=/etc/iva/ru.cidr
LIST6=/etc/iva/ru6.cidr
TMP=$(mktemp)
trap 'rm -f "$TMP" "$TMP".*' EXIT

# Жив ли домашний выход. wg: свежий handshake (<300 с). socks: телефон/компьютер держит ssh -R, sshd слушает порт.
alive() {
  if [ "$TRANSPORT" = socks ]; then
    ss -Htln "sport = :$SOCKS_PORT" | grep -q . && ip link show "$IFACE" up >/dev/null 2>&1
  else
    local hs; hs=$(wg show "$IFACE" latest-handshakes 2>/dev/null | awk '{print $2}' | sort -n | tail -1)
    [ -n "$hs" ] && [ $(( $(date +%s) - hs )) -le 300 ]
  fi
}
if ! alive; then
  ip route flush table $TABLE 2>/dev/null
  echo "домашний выход ($TRANSPORT/$IFACE) не отвечает — таблица $TABLE очищена, RU идёт напрямую"; exit 1
fi

# Правила маршрутизации (идемпотентно, v4 и v6):
#  101: ответы на входящие через WAN соединения (SSH, вебхуки, ssh -R с телефона) идут как раньше, через main —
#       иначе ответ российскому клиенту ушёл бы в туннель;
#  102: всё остальное сначала смотрит в таблицу 100 (RU-префиксы), не нашло — main.
for v in 4 6; do
  ip -$v rule show | grep -q 'fwmark 0x2000000/0x2000000 lookup main' || ip -$v rule add pref 101 fwmark 0x2000000/0x2000000 lookup main
  ip -$v rule show | grep -q "lookup $TABLE" || ip -$v rule add pref 102 lookup $TABLE
  IPT=iptables; [ $v = 6 ] && IPT=ip6tables
  for R in "PREROUTING -i $WAN -m conntrack --ctstate NEW -j CONNMARK --set-xmark 0x2000000/0x2000000" \
           "PREROUTING -j CONNMARK --restore-mark --mask 0x2000000" "OUTPUT -j CONNMARK --restore-mark --mask 0x2000000"; do
    $IPT -t mangle -C $R -m comment --comment iva-ru 2>/dev/null || $IPT -t mangle -A $R -m comment --comment iva-ru
  done
done

# IPv6 к РФ: выход только IPv4, а у VPS свой IPv6 напрямую. Российские IPv6-префиксы делаем unreachable —
# браузер/Node/curl мгновенно откатываются на IPv4, который уже идёт через туннель.
if [ -z "$(find "$LIST6" -mmin -1440 2>/dev/null)" ]; then
  curl -fsSL --max-time 90 https://www.ipdeny.com/ipv6/ipaddresses/aggregated/ru-aggregated.zone -o "$TMP.6" \
    && grep -E '^[0-9a-fA-F:]+/[0-9]{1,3}$' "$TMP.6" | sort -u > "$TMP.6list" \
    && [ "$(wc -l < "$TMP.6list")" -gt 500 ] && mv "$TMP.6list" "$LIST6"
fi
if [ -s "$LIST6" ] && [ "$(ip -6 route show table $TABLE 2>/dev/null | wc -l)" != "$(wc -l < "$LIST6")" ]; then
  sed "s|.*|route replace unreachable & table $TABLE|" "$LIST6" > "$TMP.batch6"
  ip -6 route flush table $TABLE 2>/dev/null
  ip -6 -batch "$TMP.batch6"
  echo "IPv6 РФ-префиксов (unreachable → IPv4 через туннель): $(ip -6 route show table $TABLE | wc -l)"
fi

FRESH=0
if [ -z "$(find "$LIST" -mmin -1440 2>/dev/null)" ]; then
  for URL in \
    https://www.ipdeny.com/ipblocks/data/aggregated/ru-aggregated.zone \
    https://raw.githubusercontent.com/herrbischoff/country-ip-blocks/master/ipv4/ru.cidr
  do
    if curl -fsSL --max-time 90 "$URL" -o "$TMP"; then break; fi
  done
  grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$' "$TMP" | sort -u > "$TMP.list" || true
  N=$(wc -l < "$TMP.list")
  if [ "$N" -gt 1000 ]; then mv "$TMP.list" "$LIST"; FRESH=1
  else echo "подозрительно мало префиксов: $N, беру прежний список"; fi
fi
[ -s "$LIST" ] || { echo "списка $LIST нет"; exit 1; }

# Список не менялся и таблица уже полная — ничего не трогаем.
[ "$FRESH" = 0 ] && [ "$(ip route show table $TABLE 2>/dev/null | wc -l)" = "$(wc -l < "$LIST")" ] && exit 0

sed "s|.*|route replace & dev $IFACE table $TABLE|" "$LIST" > "$TMP.batch"
ip route flush table $TABLE 2>/dev/null
ip -batch "$TMP.batch"
echo "маршрутов через $IFACE в таблице $TABLE: $(ip route show table $TABLE | wc -l)"
