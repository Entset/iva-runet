#!/usr/bin/env bash
# report.sh [since] — numbers for human-v2 from ~/.iva-browser/logs/human-v2.jsonl (+ sessions, blocks, IP checks).
# since: anything `date -d` understands, default "7 days ago". Site filter: SITE=avito.ru ./report.sh
set -u
ST=${RUWEB_HOME:-$HOME/.iva-browser}
J=$ST/logs/human-v2.jsonl
SINCE=$(date -d "${1:-7 days ago}" +%s)
[ -s "$J" ] || { echo "нет данных: $J"; exit 1; }

echo "== Действия с $(date -d @"$SINCE" '+%F %T') ${SITE:+(сайт $SITE)}"
jq -s --argjson since "$SINCE" --arg site "${SITE:-}" '
  map(select((.t // 0) >= $since)
      | select($site == "" or .site == $site)) as $a
  | ($a | map(select(.pause >= 0) | .pause) | sort) as $p
  | ($a | map(select(.act == "open" or .act == "click" or .act == "back" or .act == "forward" or .act == "reload"))) as $nav
  | {
      "действий": ($a | length),
      "по типам": ($a | group_by(.act) | map({key: .[0].act, value: length}) | from_entries),
      "интервал между действиями, с (среднее)": (if ($p | length) > 0 then (($p | add) / ($p | length) * 10 | round / 10) else null end),
      "интервал, с (медиана)": (if ($p | length) > 0 then $p[($p | length) / 2 | floor] else null end),
      "переходов": ($nav | length),
      "доля кликов среди переходов, %": (if ($nav | length) > 0 then (($nav | map(select(.how == "click")) | length) * 100 / ($nav | length) | round) else null end),
      "блоков": ($a | map(select(.block != "")) | length),
      "блоков на 100 переходов": (if ($nav | length) > 0 then (($a | map(select(.block != "")) | length) * 100 / ($nav | length) * 10 | round / 10) else null end),
      "сессий в журнале": ($a | map(.sid) | unique | map(select(. != "-")) | length)
    }' "$J"

echo "== Сессии (strict)"
awk -v t="$SINCE" -v s="${SITE:-}" '$2>=t && (s=="" || $1==s) {n++; d=($3-$2)/60; sum+=d; a+=$4; printf "  %s %s  %.1f мин  %d действий\n", $1, strftime("%F %H:%M", $2), d, $4}
  END {if (n) printf "  итого %d, средняя длительность %.1f мин, действий в среднем %.1f\n", n, sum/n, a/n; else print "  нет"}' "$ST/sessions"

echo "== Блоки (файл blocks)"
awk -v t="$SINCE" '$3>=t {printf "  %s %s\n", $1, strftime("%F %H:%M", $3)}' "$ST/blocks"

echo "== Согласованность IP"
echo "  российские сайты видят: $(curl -s -m 10 https://ip.mail.ru | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | head -1) (ожидается домашний IP)"
echo "  WebRTC в профиле: $(jq -r '.webrtc.ip_handling_policy // "НЕ ЗАДАН"' "$ST/profile/Default/Preferences" 2>/dev/null)"
IFACE=$(. /etc/iva/tunnel.env 2>/dev/null; echo "${IFACE:-wg0}")
if [ -s "$ST/logs/hosts.avito.ru" ]; then
  echo "  хосты на страницах Авито мимо туннеля (виден IP сервера):"
  sort -u "$ST/logs/hosts.avito.ru" | while read -r h; do
    ip=$(getent ahostsv4 "$h" | awk '{print $1; exit}'); [ -n "$ip" ] || continue
    ip route get "$ip" 2>/dev/null | grep -q "dev $IFACE" || echo "    $h $ip"
  done
fi
