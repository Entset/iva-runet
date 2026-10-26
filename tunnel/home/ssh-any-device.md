# Дом: любой компьютер — Windows, macOS, Linux (SSH, без настройки роутера)

Самый простой путь, если роутер обычный. На домашнем компьютере одна команда `ssh -R`:
VPS получает SOCKS-прокси, который выходит в интернет из дома. Никаких программ, кроме
встроенного OpenSSH (есть в Windows 10/11, macOS, любом Linux), прав администратора не нужно.

Сервер: `install-ssh-socks.sh` (транспорт SSH). Ограничения:
- только TCP (сайты и API работают; UDP/QUIC — нет, браузер сам переходит на TCP);
- компьютер должен быть включён и не спать, пока Ива ходит на российские сайты;
- когда он выключен, Ива через 5 минут автоматически ходит напрямую (с IP VPS).

## 1. Ключ (один раз)

Windows (PowerShell), macOS/Linux (терминал) — одинаково:

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/iva_tunnel -C iva-home
cat ~/.ssh/iva_tunnel.pub          # ← эту строку отдать на сервер: sudo bash add-device.sh "<строка>"
```

Ключ на VPS умеет только одно — слушать 127.0.0.1:1080. Шелла и команд у него нет.

## 2. Проверка вручную

```bash
ssh -N -R 127.0.0.1:1080 -i ~/.ssh/iva_tunnel -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes ivatun@<VPS_IP>
```

Команда «висит» без вывода — так и надо. На сервере: `bash tunnel/server/check.sh` → «устройство на связи: да».

## 3. Автозапуск

**Linux** — `~/.config/systemd/user/iva-tunnel.service`:

```ini
[Unit]
Description=Iva home exit (ssh -R)
After=network-online.target

[Service]
ExecStart=/usr/bin/ssh -N -R 127.0.0.1:1080 -i %h/.ssh/iva_tunnel -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new ivatun@<VPS_IP>
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
```

```bash
systemctl --user enable --now iva-tunnel
sudo loginctl enable-linger $USER     # работать и без входа в систему
```

**macOS** — `~/Library/LaunchAgents/iva.tunnel.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>iva.tunnel</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/ssh</string><string>-N</string><string>-R</string><string>127.0.0.1:1080</string>
    <string>-i</string><string>/Users/<ИМЯ>/.ssh/iva_tunnel</string>
    <string>-o</string><string>ServerAliveInterval=30</string>
    <string>-o</string><string>ExitOnForwardFailure=yes</string>
    <string>-o</string><string>StrictHostKeyChecking=accept-new</string>
    <string>ivatun@<VPS_IP></string>
  </array>
  <key>KeepAlive</key><true/>
  <key>RunAtLoad</key><true/>
</dict></plist>
```

```bash
launchctl load ~/Library/LaunchAgents/iva.tunnel.plist
```

В «Настройки → Аккумулятор» отключить сон при подключении к сети, иначе туннель засыпает вместе с Mac.

**Windows** — файл `C:\Users\<ИМЯ>\iva-tunnel.cmd`:

```bat
@echo off
:loop
ssh -N -R 127.0.0.1:1080 -i %USERPROFILE%\.ssh\iva_tunnel -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new ivatun@<VPS_IP>
timeout /t 10 >nul
goto loop
```

Планировщик заданий → Создать задачу: триггер «При входе в систему» (или «При запуске» + «Выполнять
вне зависимости от входа»), действие — этот `.cmd`. В электропитании отключить сон.

## Откат

Остановить автозапуск, удалить `~/.ssh/iva_tunnel*`. На сервере убрать строку ключа из
`~ivatun/.ssh/authorized_keys`.
