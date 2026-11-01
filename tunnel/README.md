# Российский IP через дом или офис

Только трафик к российским адресам идёт через дом, остальное — напрямую с VPS.
Дом сам подключается к VPS, поэтому белый IP не нужен. Если дом недоступен дольше 5 минут, Ива ходит напрямую.

## Выбор

| Дома | Транспорт | Инструкция |
|---|---|---|
| OpenWrt | WireGuard | [home/openwrt.md](home/openwrt.md) |
| Keenetic, MikroTik | WireGuard | [home/other-routers.md](home/other-routers.md) (не проверено на устройстве) |
| Linux, включённый всегда | WireGuard | [home/linux.md](home/linux.md) |
| Windows / macOS, включённый всегда | SSH | [home/ssh-any-device.md](home/ssh-any-device.md) |
| Android-телефон | SSH | [home/android.md](home/android.md) |

Обычный роутер (провайдерский, TP-Link, ASUS) не настраиваем — выходом служит устройство за ним.
WireGuard быстрее и надёжнее; SSH проще (одна команда, без прав администратора), только TCP.

## Сервер

| Скрипт | Что делает |
|---|---|
| `server/install-wireguard.sh` | WireGuard; печатает ключ и адрес для дома |
| `server/add-peer.sh <ключ>` | подключить дом (WireGuard) |
| `server/install-ssh-socks.sh` | SSH-вариант |
| `server/add-device.sh "<ssh-ключ>"` | подключить устройство (SSH-транспорт) |
| `server/enable-routes.sh` | включить маршруты и проверить |
| `server/repair-routes-timer.sh` | восстановить автозапуск маршрутов после перезагрузки |
| `server/check.sh` | диагностика |
| `server/rollback.sh` | откат |

## Маршруты после перезагрузки

Выбранный транспорт и `iva-ru-routes.timer` должны быть включены в автозапуск. Таймер проверяет домашний выход через минуту после загрузки VPS, через 10 секунд после своей активации и затем каждые 5 минут. Как только дом доступен, российские IPv4-маршруты возвращаются в таблицу `100`: через `wg0` для WireGuard или `ivasocks` для SSH.

Если после перезагрузки маршруты не вернулись, из корня репозитория выполни:

```sh
sudo bash tunnel/server/repair-routes-timer.sh
```

Скрипт сохраняет копию своего drop-in, записывает `/etc/systemd/system/iva-ru-routes.timer.d/zz-startup-recovery.conf`, включает и перезапускает таймер, затем сразу запускает существующую проверку маршрутов. Транспорт не перезапускается. Имя drop-in выбрано так, чтобы правило загружалось после старого `override.conf`; пустые значения интервалов в старой настройке могут сбросить триггеры запуска. При недоступном доме скрипт сообщает об этом, а таймер продолжает повторять проверку каждые 5 минут.

Проверка:

```sh
systemctl is-enabled iva-ru-routes.timer
systemctl status iva-ru-routes.timer --no-pager
systemctl show iva-ru-routes.timer -p TimersMonotonic
ip route get 77.88.8.8
```

В `TimersMonotonic` должны быть `OnBootUSec`, `OnActiveUSec` и `OnUnitActiveUSec`. При доступном доме маршрут должен содержать `dev wg0` (или `dev ivasocks`) и `table 100`. Автозапуск транспорта: `systemctl is-enabled wg-quick@wg0.service` для WireGuard или `systemctl is-enabled iva-socks-tun.service` для SSH. После перезагрузки дома WireGuard должен подключиться сам, а SSH-устройство — восстановить `ssh -R` через настроенный автозапуск.

## Если что-то поменялось

- IP VPS — поменять адрес на домашней стороне.
- Домашний IP — ничего.
- Переустановка VPS — сохранить `/etc/wireguard/server.key` заранее, тогда дома ничего не менять.
