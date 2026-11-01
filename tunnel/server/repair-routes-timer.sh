#!/usr/bin/env bash
# Восстановить автозапуск RU-маршрутов без перезапуска транспорта.
set -euo pipefail

if [[ ${1:-} == --help ]]; then
  echo 'Usage: sudo bash tunnel/server/repair-routes-timer.sh'
  echo 'Сохраняет копию своего drop-in, включает таймер и запускает обновление маршрутов.'
  exit 0
fi
[[ $# == 0 ]] || { echo 'Неизвестный аргумент; см. --help.' >&2; exit 2; }
[[ $(id -u) == 0 ]] || { echo 'Запусти через sudo bash.' >&2; exit 1; }
[[ -x /usr/local/bin/iva-ru-routes.sh ]] || { echo 'Скрипт маршрутов не установлен.' >&2; exit 1; }
[[ $(systemctl show iva-ru-routes.timer -p LoadState --value) == loaded ]] || {
  echo 'Таймер маршрутов не установлен.' >&2; exit 1;
}

# Старые установки WireGuard могут ещё не иметь tunnel.env.
TRANSPORT=wg
IFACE=wg0
[[ ! -f /etc/iva/tunnel.env ]] || . /etc/iva/tunnel.env

dropin_dir=/etc/systemd/system/iva-ru-routes.timer.d
# Загружается после старого override.conf: пустые интервалы в нём могут сбрасывать триггеры.
dropin=$dropin_dir/zz-startup-recovery.conf
install -d -m 755 "$dropin_dir"
if [[ -e $dropin ]]; then
  cp -a -- "$dropin" "$dropin.backup.$(date -u +%Y%m%dT%H%M%S).$$"
fi
umask 022
cat > "$dropin" <<'EOF'
[Timer]
OnBootSec=
OnBootSec=1min
OnActiveSec=10s
OnUnitActiveSec=5min
EOF
systemctl daemon-reload
systemctl enable iva-ru-routes.timer
systemctl restart iva-ru-routes.timer

echo '== Восстановление маршрутов с существующей проверкой домашнего выхода'
route_ok=1
systemctl start iva-ru-routes.service || route_ok=0
systemctl list-timers --all iva-ru-routes.timer --no-pager
systemctl show iva-ru-routes.timer -p TimersMonotonic
journalctl -u iva-ru-routes.service -n 12 --no-pager
echo '== Маршрут к российскому DNS'
route=$(ip route get 77.88.8.8)
echo "$route"
if [[ $route_ok == 1 ]] && [[ " $route " == *" dev $IFACE "* ]] && [[ " $route " == *" table 100 "* ]]; then
  echo 'Маршруты восстановлены. Автозапуск и повтор каждые 5 минут включены.'
else
  echo "Таймер восстановлен; маршруты через $TRANSPORT/$IFACE пока не восстановлены." >&2
  echo 'Проверь домашний выход и журнал выше. Таймер повторит проверку через 5 минут.' >&2
  exit 1
fi
