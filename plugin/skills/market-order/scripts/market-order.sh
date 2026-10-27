#!/usr/bin/env bash
# market-order.sh — помощник навыка market-order (Яндекс Маркет + Wildberries).
# ЧИТАЙ skills/market-order/SKILL.md перед использованием. Кнопку «Оформить заказ»/
# «Оплатить» нажимает ТОЛЬКО владелец (stop()/правило №1 в SKILL.md).
#
#   stage [market|wb] [--mcp up|down] - стадия: READY(GUEST|AUTH)|NO_MCP|NO_LOGIN|BLOCK
#   login open                        - WB: открыть вход, ввести телефон, ждать SMS-код
#   login enter CODE                  - WB: ввести код из SMS (код присылает владелец в чат)
#   state-save                        - сохранить вход WB -> state-wb.json (600, бэкап)
#   search wb QUERY                   - WB: поиск браузером (MCP wb_* с сервера 403)
#   search market QUERY [--browser]   - Маркет: подсказка MCP; фолбэк браузером по флагу
#   cart wb URL|ID                    - WB: карточка -> «Добавить в корзину» -> корзина -> СТОП
#   cart market URL|ID                - Маркет: карточка -> «В корзину» -> корзина -> СТОП
#   tiles [N]                         - выдача на экране -> N первых товаров: «название | цена | URL | скрин плитки»
#   status                            - что на экране; предупреждение, если видна кнопка оформления
#   close                             - закрыть сеанс, убрать tmp
#
# URL|ID: полный адрес карточки или артикул WB (ID -> URL сам).
# Коды выхода: 2 BLOCK_COOLDOWN, 3 NO_MCP, 4 NO_LOGIN, 10 NO_BROWSER,
#              11 NO_CONFIG, 12 NO_STATE, 13 NOT_CONFIGURED, 14 NO_BUTTON
set -u
CONF="${MARKET_ORDER_CONFIG:-$HOME/.config/market-order/config.env}"
DIR="$HOME/.config/market-order"
STATE_MARKET="$DIR/state.json"          # cookies Яндекса для Маркета (копия taxi-state)
STATE_WB="$DIR/state-wb.json"           # вход WB (см. login/state-save)
TAXI_STATE="${TAXI_STATE:-$HOME/.config/yandex-taxi-skill/state.json}"
TMP="${MARKET_ORDER_TMP:-/tmp/market-order}"
RUWEB="${RUWEB:-}"   # empty: need_ruweb finds it

PHONE_WB=""; DEFAULT_MODE=GUEST
[ -f "$CONF" ] && . "$CONF"
mkdir -p "$TMP"
cmd="${1:-help}"; [ $# -gt 0 ] && shift || true
AB() { agent-browser --session ruweb --profile "$HOME/.iva-browser/profile" "$@"; }

need_conf() { [ -f "$CONF" ] || { echo "NO_CONFIG: нет $CONF (шаблон config.example.env)"; exit 11; }; }
# ruweb: the sibling skill when both ship in the runet plugin, else an installed ru-web/runet plugin
need_ruweb() { [ -x "$RUWEB" ] || RUWEB=$(ls "$(dirname "$(readlink -f "$0")")"/../../ru-web/scripts/ruweb \
    "$HOME"/iva/data/custom/plugins/{ru-web,runet}/skills/ru-web/scripts/ruweb 2>/dev/null | head -1)
  command -v agent-browser >/dev/null 2>&1 || { echo "NO_BROWSER: agent-browser не найден"; exit 10; }
  [ -n "$RUWEB" ] && [ -x "$RUWEB" ] || { echo "ERR: ruweb не найден"; exit 10; }; }
# открывать ТОЛЬКО через ruweb (голый браузер на Маркете = 403, проверено 2026-10-26)
open_url() { need_ruweb; "$RUWEB" open "$1"; }
snap() { AB snapshot -i 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'; }
shot() { f="$TMP/$1-$(date +%H%M%S).png"; AB screenshot "$f" >/dev/null 2>&1 && echo "SHOT: $f"; }
block_check() { f="$TMP/cooldown-$1"
  if [ -f "$f" ]; then echo "BLOCK: $1 в паузе до $(cat "$f" 2>/dev/null) (см. references/05-errors.md)"; exit 2; fi; }
urlenc() { python3 -I - "$1" <<'PY'
import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))
PY
}
ref_of() { # подстрока имени кнопки в snapshot -> ref (пусто = нет)
  snap | grep -F "button \"$1" | grep -oE 'ref=e[0-9]+' | head -1 | cut -d= -f2
}
click_ref() { r="$1"
  if [ -z "$r" ]; then echo "NO_BUTTON: кнопка не найдена (references/05-errors.md)"; exit 14; fi
  AB click "@$r" >/dev/null 2>&1; sleep 2; }
fill_ref() { AB fill "@$1" "$2" >/dev/null 2>&1; sleep 1; }
stop() { # главный предохранитель — печатать перед завершением корзины
  cat <<'EOS'
STOP_BEFORE_CHECKOUT: ** Кнопку «Оформить заказ»/«Оплатить» нажимает ТОЛЬКО владелец. **
Ива останавливается: ссылка на корзину + сумма текстом; карту, 3DS, SMS-код НЕ вводить; заказ не оформлять.
EOS
}
find_checkout_button() { # только КОНСТАТАЦИЯ, никакого нажатия
  snap | grep -iE 'button "(Перейти к оформлению|Оформить заказ|Войти и оформить|Оплатить|Заказать)' | head -2
}
# --- WB вход ----------------------------------------------------------------
wb_login_gate() {
  case "$PHONE_WB" in ''|*999*) echo "NOT_CONFIGURED: PHONE_WB не заполнен в $CONF"; exit 13;; esac
}
wb_login_open() {
  wb_login_gate
  open_url "https://www.wildberries.ru/" || exit 2
  sleep 3
  r=$(ref_of "Войти")
  if [ -z "$r" ]; then echo "NO_BUTTON: кнопки «Войти» нет — возможно, уже вошли (проверь status); references/03-wb.md"; exit 14; fi
  click_ref "$r"; sleep 2
  ref=$(snap | grep -iE '(textbox|input).*\+?7|textbox "(Телефон|Номер)' | grep -oE 'ref=e[0-9]+' | head -1 | cut -d= -f2)
  if [ -z "$ref" ]; then echo "NO_BUTTON: поле телефона не найдено (капча? -> СТОП, references/05-errors.md)"; exit 14; fi
  fill_ref "$ref" "$PHONE_WB"
  r=$(ref_of "Продолжить"); [ -n "$r" ] || r=$(ref_of "Получить код")
  click_ref "$r"
  echo "WAIT_CODE: код из SMS — присылает владелец в чат. Дальше: market-order.sh login enter CODE"
  echo "СТОП: капча/«подтвердите что не робот» — НЕ обходить, сообщить владельцу (references/05-errors.md)."
}
wb_login_enter() {
  code="${1:-}"; [ -n "$code" ] || { echo "ERR: login enter CODE"; exit 13; }
  ref=$(snap | grep -iE '(textbox|input).*(код|code)' | grep -oE 'ref=e[0-9]+' | head -1 | cut -d= -f2)
  if [ -z "$ref" ]; then echo "NO_BUTTON: поле кода не видно — повтори login open или это капча"; exit 14; fi
  fill_ref "$ref" "$code"
  r=$(ref_of "Продолжить"); [ -n "$r" ] || r=$(ref_of "Войти"); [ -n "$r" ] || r=$(ref_of "Подтвердить")
  [ -n "$r" ] && click_ref "$r"
  sleep 3
  if snap | grep -qF 'button "Войти"'; then echo "LOGIN_FAIL: «Войти» всё ещё видна — код неверный или устарел"; exit 4; fi
  echo "LOGIN_OK: вход WB выполнен. Сохранить: market-order.sh state-save"
}
state_save() {
  t="$TMP/state-new.json"; rm -f "$t"; ok=0
  for try in 1 2 3; do # демон agent-browser иногда отвечает EAGAIN — повтор с паузой
    AB state save "$t" >/dev/null 2>&1 && [ -s "$t" ] && { ok=1; break; }; sleep 4
  done
  [ $ok = 1 ] || { echo "SAVE_FAIL: state save не сработал за 3 попытки (references/05-errors.md)"; exit 12; }
  python3 -I - "$t" <<'PY' >/dev/null 2>&1 || { echo "SAVE_FAIL: файл не JSON"; rm -f "$t"; exit 12; }
import json, sys; d = json.load(open(sys.argv[1])); assert d.get("cookies")
PY
  chmod 600 "$t"; mkdir -p "$DIR"; chmod 700 "$DIR" 2>/dev/null
  [ -f "$STATE_WB" ] && cp -p "$STATE_WB" "${STATE_WB%.json}.bak.json"
  cp "$t" "$STATE_WB" && chmod 600 "$STATE_WB" && rm -f "$t"
  echo "СОХРАНЕНО: $STATE_WB (600; бэкап: ${STATE_WB%.json}.bak.json)"
}
# --- поиск ------------------------------------------------------------------
search_wb() { q="${1:-}"; [ -n "$q" ] || { echo "ERR: search wb ТЕКСТ"; exit 13; }
  open_url "https://www.wildberries.ru/catalog/0/search.aspx?search=$(urlenc "$q")" || exit 2
  sleep 4
  snap | grep -E 'link ".{10,}"' | head -12
  echo "СЛЕДУЮЩЕЕ: карточка -> cart wb <URL| артикул>; MCP wb_search/wb_card с сервера 403 (2026-10-26) — только браузер."
}
search_market() { q="${1:-}"; [ -n "$q" ] || { echo "ERR: search market ТЕКСТ"; exit 13; }
  echo "ПЕРВЫЙ ВЫБОР — MCP (браузер не нужен): yandex_search, yandex_card, compare_prices (коннектор marketplace)."
  echo "Фолбэк браузером (только если MCP недоступен):"
  echo "  market-order.sh search market '$q' --browser"
  case "${2:-}" in --browser) open_url "https://market.yandex.ru/search?text=$(urlenc "$q")" || exit 2
    sleep 4; snap | grep -E 'link ".{10,}"' | head -12;; esac
}
# --- плитки выдачи: название, цена, ссылка + скрин плитки (Ozon/WB/Маркет, любой движок ruweb) ---
# ponytail: плитка = ближайший предок ссылки на товар с «₽» и картинкой; новая площадка — проверить глазами
TILE_JS='(()=>{const k=__I__;document.querySelectorAll("[data-iva-pick]").forEach(e=>e.removeAttribute("data-iva-pick"));
const seen=new Set(),tiles=[];for(const a of document.querySelectorAll("a[href*=\"/product\"],a[href*=\"/detail.aspx\"],a[href*=\"/card/\"]")){
const u=a.href.split("?")[0];if(seen.has(u))continue;let t=a;for(let i=0;i<8&&t.parentElement;i++){t=t.parentElement;if(/₽/.test(t.innerText)&&t.querySelector("img"))break}
const name=t.innerText.split("\n").find(s=>s.length>25);if(!name||!/₽/.test(t.innerText))continue;seen.add(u);
tiles.push([t,name.slice(0,100)+" | "+(t.innerText.match(/\d[\d\s  ]*₽/)||[""])[0].replace(/\s/g," ")+" | "+u])}
const x=tiles[k];if(!x)return "";x[0].setAttribute("data-iva-pick","1");x[0].scrollIntoView({block:"center"});return x[1]})()'
tiles_cmd() { n="${1:-5}"; need_ruweb
  out="$HOME/iva/data/vault/attachments/outgoing/$(date +%F)"; mkdir -p "$out"
  for i in $(seq 0 $((n-1))); do
    line=$("$RUWEB" eval "${TILE_JS//__I__/$i}" 2>/dev/null | sed 's/^"//; s/"$//')
    [ -n "$line" ] || { [ "$i" = 0 ] && echo "NO_TILES: на экране нет выдачи с товарами"; break; }
    sleep 1; f="$out/tile-$(date +%H%M%S)-$((i+1)).png"
    "$RUWEB" screenshot '[data-iva-pick]' "$f" >/dev/null 2>&1 || f="(скрин не снялся)"
    echo "$((i+1)). $line | ${f#*/vault/attachments/}"
  done
}
# --- корзина ----------------------------------------------------------------
wb_item_url() { case "$1" in http*) echo "$1";; *) echo "https://www.wildberries.ru/catalog/$1/detail.aspx";; esac; }
cart_wb() { u=$(wb_item_url "${1:-}")
  [ -n "$u" ] || { echo "ERR: cart wb URL|артикул"; exit 13; }
  open_url "$u" || exit 2; sleep 4
  r=$(ref_of "Добавить в корзину"); [ -n "$r" ] || r=$(ref_of "В корзину")
  if [ -z "$r" ]; then echo "NO_BUTTON: «Добавить в корзину» не найдено (нет в наличии? references/03-wb.md, 05-errors.md)"; snap | tail -20; exit 14; fi
  click_ref "$r"; sleep 2
  open_url "https://www.wildberries.ru/cartorder" 2>/dev/null || true; sleep 4
  echo "CART_WB:"; find_checkout_button | sed 's/^/  ВИДНА КНОПКА ОФОРМЛЕНИЯ: /'
  snap | tail -40; echo "CART_URL: $(AB get url 2>/dev/null)"; stop
  echo "ДАЛЬШЕ (только владелец): «Войти и оформить». Удалить товар: крестик в корзине (references/03-wb.md)."
}
cart_market() { u="${1:-}"
  case "$u" in http*) : ;; *) u="https://market.yandex.ru/product--$u";; esac
  [ -n "$u" ] || { echo "ERR: cart market URL|ID"; exit 13; }
  open_url "$u" || exit 2; sleep 4
  r=$(ref_of "В корзину"); [ -n "$r" ] || r=$(ref_of "Добавить в корзину")
  if [ -z "$r" ]; then echo "NO_BUTTON: «В корзину» не найдено (нет в наличии? references/02-market.md, 05-errors.md)"; snap | tail -20; exit 14; fi
  click_ref "$r"; sleep 2
  open_url "https://market.yandex.ru/my/cart" || exit 2; sleep 4
  echo "CART_MARKET:"; find_checkout_button | sed 's/^/  ВИДНА КНОПКА ОФОРМЛЕНИЯ: /'
  snap | tail -40; echo "CART_URL: $(AB get url 2>/dev/null)"; stop
  echo "ДАЛЬШЕ (только владелец): «Перейти к оформлению». Удалить: корзина -> «Удалить» (references/02-market.md)."
}
status_cmd() {
  echo "URL: $(AB get url 2>/dev/null)"; snap | tail -30; shot status
  b=$(find_checkout_button)
  [ -n "$b" ] && { echo "$b" | sed 's/^/  ВИДНА КНОПКА ОФОРМЛЕНИЯ: /'; stop; }
  exit 0
}
close_cmd() { AB close >/dev/null 2>&1; rm -rf "$TMP"; echo closed; }

case "$cmd" in
stage)
  site="${1:-market}"; mcp=up
  if [ "${2:-}" = "--mcp" ] && [ "${3:-}" = "down" ]; then mcp=down; fi
  block_check "$site"
  case "$site" in
    market)
      [ "$mcp" = up ] || { echo "NO_MCP: коннектор marketplace не отвечает — поиск браузером через ruweb или отложить"; exit 3; }
      if [ -s "$STATE_MARKET" ]; then echo "AUTH: cookies Маркета есть ($STATE_MARKET); STAGE=READY (AUTH)"; exit 0; fi
      if [ -s "$TAXI_STATE" ]; then echo "GUEST: своего state нет, есть taxi-state Яндекса — подложить (references/02-market.md); STAGE=READY (GUEST)"; exit 0; fi
      echo "NO_LOGIN: cookies Яндекса нет; STAGE=NO_LOGIN -> references/02-market.md"; exit 4;;
    wb)
      [ "$mcp" = up ] || { echo "MCP_WB_DOWN: WB API 403 с сервера (известно с 2026-10-26) — WB только браузером (references/03-wb.md)"; exit 3; }
      if [ -s "$STATE_WB" ]; then echo "AUTH: вход WB сохранён ($STATE_WB); STAGE=READY (AUTH)"; exit 0; fi
      echo "GUEST: входа WB нет — корзина гостем (STAGE=READY GUEST); AUTH: market-order.sh login open (SMS-код пришлёт владелец)"; exit 0;;
    *) echo "ERR: stage market|wb"; exit 13;;
  esac;;
login) sub="${1:-}"
  case "$sub" in
    open) wb_login_open;;
    enter) wb_login_enter "${2:-}";;
    *) cat <<'EOS'
WB вход (AUTH-режим; SMS-код присылает владелец в чат, Ива его не запрашивает сама):
  1. market-order.sh login open         # открыть вход, подставить телефон из конфига
  2. владелец присылает код             # код приходит только от владельца
  3. market-order.sh login enter CODE   # ввести код
  4. market-order.sh state-save         # -> ~/.config/market-order/state-wb.json (600)
Капча/«подтвердите, что не робот» — стоп, не обходить (references/05-errors.md).
EOS
  esac;;
state-save) state_save;;
search) case "${1:-}" in
    wb) search_wb "${2:-}";;
    market) search_market "${2:-}" "${3:-}";;
    *) echo "ERR: search wb|market ТЕКСТ"; exit 13;; esac;;
cart) case "${1:-}" in
    wb) cart_wb "${2:-}";;
    market) cart_market "${2:-}";;
    *) echo "ERR: cart wb|market URL|ID"; exit 13;; esac;;
tiles) tiles_cmd "${1:-5}";;
status) status_cmd;;
close) close_cmd;;
help) sed -n '2,/^set -u$/p' "$0" | sed -e 's/^# \{0,2\}//' -e '$d';;
esac