# Домашний браузер — для Самоката, Перекрёстка, Купера и похожих

Эти сайты защищены ServicePipe: он проверяет сам браузер (система, видеокарта, шрифты) и отличает Chrome
на сервере от настоящего, даже с домашним IP и прогревом. Поэтому для них Ива управляет **настоящим Chrome
на домашнем или офисном компьютере** — отдельным окном с отдельным профилем.

Нужен компьютер Windows / macOS / Linux с графикой, включённый, пока Ива работает с этими сайтами.
Работает при любом транспорте (WireGuard или SSH).

## 1. Проверка: открывается ли у вас вообще

В обычном браузере дома откройте samokat.ru, perekrestok.ru, kuper.ru. Если и у вас «Forbidden» /
«Проблемы со связью» — заблокирован сам домашний IP; подождите сутки, домашний браузер не поможет.

## 2. Отдельный Chrome для Ивы

Отдельный профиль обязателен: через этот порт можно управлять всем, что открыто в профиле.
Не входите в нём в почту и банк.

**Windows** (ярлык или `.cmd`):
```bat
"C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir=%USERPROFILE%\iva-chrome
```

**macOS:**
```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --remote-debugging-port=9222 --user-data-dir=$HOME/iva-chrome
```

**Linux:**
```bash
google-chrome --remote-debugging-port=9222 --user-data-dir=$HOME/iva-chrome
```

Порт слушается только на этом компьютере (127.0.0.1), из домашней сети его не видно.

## 3. Связь с сервером

Ключ — как в [ssh-any-device.md](ssh-any-device.md) (шаг 1), на сервере `sudo bash add-device.sh "<ключ>"`. Затем:

```bash
ssh -N -R 127.0.0.1:9222:127.0.0.1:9222 -i ~/.ssh/iva_tunnel -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes ivatun@<VPS_IP>
```

Уже используете SSH-транспорт с этого компьютера — добавьте `-R 127.0.0.1:9222:127.0.0.1:9222` в ту же команду.
Автозапуск — как там же (шаг 3).

## 4. На сервере

В `~/.iva-browser/sites.txt` нужные сайты с флагом `home`:

```
samokat.ru home
perekrestok.ru home
kuper.ru home
```

Проверка: `ruweb status` → `home browser: up`; `ruweb open https://samokat.ru/` — страница откроется в окне дома.
Окно Ивы не закрывайте и не трогайте, пока она работает. Если компьютер выключен — Ива ответит `HOME_DOWN` и скажет вам.
