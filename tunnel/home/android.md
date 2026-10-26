# Дом: Android-телефон (SSH через Termux, без root)

Старый Android-телефон на зарядке может быть домашним выходом. Плюс: если он в мобильной сети, российские
сайты видят **мобильный IP** — антиботы им доверяют больше, чем домашним и тем более серверным.

Работает так же, как [ssh-any-device.md](ssh-any-device.md): телефон держит `ssh -R` к VPS.
Сервер: `install-ssh-socks.sh` (транспорт SSH).

Учти:
- **трафик** — весь RU-трафик Ивы (браузер, страницы Авито/Маркета ~2–5 МБ каждая) идёт через телефон.
  На Wi-Fi это домашний IP и безлимит; на мобильных данных — расход тарифа (и раздача может тарифицироваться отдельно —
  тут это не раздача, а обычный трафик приложения, но проверь условия оператора);
- телефон должен быть на зарядке и не убивать Termux (см. «Энергосбережение»);
- iPhone не подходит: iOS не держит фоновые соединения сутками.

## 1. Termux

Ставить из **F-Droid** (версия из Google Play устарела и не обновляет пакеты): Termux и Termux:Boot.

```bash
pkg update && pkg install -y openssh termux-api
ssh-keygen -t ed25519 -N "" -f ~/.ssh/iva_tunnel -C iva-phone
cat ~/.ssh/iva_tunnel.pub      # ← на сервер: sudo bash add-device.sh "<строка>"
```

## 2. Проверка вручную

```bash
termux-wake-lock
ssh -N -R 127.0.0.1:1080 -i ~/.ssh/iva_tunnel -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new ivatun@<VPS_IP>
```

На сервере `bash tunnel/server/check.sh` → «устройство на связи: да», «IP для российских сайтов» = IP телефона.

## 3. Автозапуск после перезагрузки (Termux:Boot)

```bash
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/iva-tunnel <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
while true; do
  ssh -N -R 127.0.0.1:1080 -i ~/.ssh/iva_tunnel -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
      -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new ivatun@<VPS_IP>
  sleep 10
done
EOF
chmod +x ~/.termux/boot/iva-tunnel
```

Один раз открыть приложение Termux:Boot, затем перезагрузить телефон и проверить на сервере.

## Энергосбережение (иначе Android убьёт соединение)

- Настройки → Приложения → Termux и Termux:Boot → Батарея → **Без ограничений**.
- Xiaomi/Redmi/POCO: ещё «Автозапуск» → вкл; Huawei/Honor: «Запуск приложений» → вручную, все три галки;
  Samsung: убрать Termux из «Спящих приложений».
- Уведомление Termux «wake lock held» должно висеть постоянно.

## Мобильная сеть или Wi-Fi

Телефон выходит туда, где он подключён: на Wi-Fi — домашний IP, на мобильных данных — мобильный.
Чтобы всегда был мобильный IP, выключи на нём Wi-Fi. Чтобы не тратить мобильный трафик — оставь Wi-Fi.

## Откат

Удалить `~/.termux/boot/iva-tunnel` и `~/.ssh/iva_tunnel*`, на сервере убрать ключ из `~ivatun/.ssh/authorized_keys`.
