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
| `server/check.sh` | диагностика |
| `server/rollback.sh` | откат |

## Если что-то поменялось

- IP VPS — поменять адрес на домашней стороне.
- Домашний IP — ничего.
- Переустановка VPS — сохранить `/etc/wireguard/server.key` заранее, тогда дома ничего не менять.
