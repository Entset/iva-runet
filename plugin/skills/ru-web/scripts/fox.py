#!/usr/bin/env python3
"""fox — Camoufox (Firefox with C++-level fingerprint) behind the agent-browser commands ruweb uses.

For sites whose anti-bot (ServicePipe: Samokat, Perekrestok; Ozon) blocks any server Chrome, warm or not.
Measured 2026-10-26 through the RU tunnel: Camoufox os=linux passes them; os=windows is blocked
(Firefox-on-Windows fingerprint over a Linux TCP stack is a mismatch). Kuper and Megamarket still show a captcha.

  fox.py <agent-browser-like command> ...   client: one command to the daemon, prints the result
  fox.py _serve PROFILE SOCK                daemon: one persistent Camoufox, one tab (started by `open`)
The client is stdlib-only; the daemon runs under the Camoufox venv (RUWEB_FOX_PY).
"""
import json, os, socket, subprocess, sys, time

ST = os.environ.get("RUWEB_HOME") or os.path.expanduser("~/.iva-browser")
SOCK = os.path.join(ST, "fox.sock")
PROFILE = os.path.join(ST, "fox-profile")
PY = os.environ.get("RUWEB_FOX_PY") or os.path.expanduser("~/.iva-browser/camoufox/venv/bin/python")

# Snapshot: visible interactive elements get data-fox-ref="eN"; `@eN` in any selector means that element.
SNAP_JS = r"""(all) => {
  const q = 'a[href],button,input:not([type=hidden]),select,textarea,[role=button],[role=link],[role=checkbox],[role=tab],[contenteditable=true]';
  let n = 0, out = [];
  document.querySelectorAll('[data-fox-ref]').forEach(e => e.removeAttribute('data-fox-ref'));
  for (const e of document.querySelectorAll(all ? '*' : q)) {
    const r = e.getBoundingClientRect(), s = getComputedStyle(e);
    if (!r.width || !r.height || s.visibility === 'hidden' || s.display === 'none') continue;
    const ref = 'e' + (++n); e.setAttribute('data-fox-ref', ref);
    const role = e.getAttribute('role') || {A: 'link', BUTTON: 'button', SELECT: 'combobox', TEXTAREA: 'textbox'}[e.tagName]
      || (e.tagName === 'INPUT' ? (['checkbox', 'radio'].includes(e.type) ? e.type : 'textbox') : e.tagName.toLowerCase());
    const name = (e.getAttribute('aria-label') || e.innerText || e.value || e.placeholder || e.title || e.alt || '').trim().replace(/\s+/g, ' ').slice(0, 80);
    const href = e.tagName === 'A' ? ' ' + e.getAttribute('href').slice(0, 100) : '';
    out.push(`- ${role} "${name}" [ref=${ref}]${href}`);
  }
  return out.join('\n');
}"""


def sel(s):
    return f'[data-fox-ref="{s[1:]}"]' if s.startswith("@e") else s


def xvfb():
    """Own 1440x900 screen (Camoufox's virtual display is 1x1: nothing to see over VNC for `ruweb captcha`).
    PDEATHSIG: Xvfb dies with the daemon, even on pkill."""
    import ctypes, signal
    disp = ":" + os.environ.get("RUWEB_FOX_DISPLAY", "88")
    lock, sock = f"/tmp/.X{disp[1:]}-lock", f"/tmp/.X11-unix/X{disp[1:]}"
    try:   # leftovers of a SIGKILLed Xvfb
        os.kill(int(open(lock).read()), 0)
        sys.exit(f"display {disp} busy")
    except (OSError, ValueError):
        for f in (lock, sock):
            if os.path.exists(f): os.unlink(f)
    pdeath = lambda: ctypes.CDLL("libc.so.6").prctl(1, signal.SIGTERM)   # PR_SET_PDEATHSIG
    subprocess.Popen(["Xvfb", disp, "-screen", "0", "1440x900x24", "-nolisten", "tcp"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=pdeath)
    for _ in range(50):
        if os.path.exists(f"/tmp/.X11-unix/X{disp[1:]}"): break
        time.sleep(0.1)
    os.environ["DISPLAY"] = disp


def serve(profile, sock_path):
    from camoufox.sync_api import Camoufox
    xvfb()
    # Yandex DoH (through the home exit like any RU address) and no IPv6 (would bypass the tunnel), as in the Chrome profile.
    prefs = {"intl.accept_languages": "ru-RU,ru", "network.dns.disableIPv6": True,
             "network.trr.mode": 3, "network.trr.uri": "https://common.dot.dns.yandex.net/dns-query",
             "network.trr.bootstrapAddr": "77.88.8.8", "browser.sessionstore.resume_from_crash": False}
    ctx = Camoufox(persistent_context=True, user_data_dir=profile, headless=False, os="linux",
                   locale="ru-RU", humanize=True, block_webrtc=True, window=(1440, 900),
                   config={"timezone": "Europe/Moscow"}, firefox_user_prefs=prefs,
                   i_know_what_im_doing=True).__enter__()
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    ctx.on("page", lambda p: p.close() if p != page else None)   # one tab only, like ruweb's close_extra_tabs
    mouse = [700, 400]
    if os.path.exists(sock_path):
        os.unlink(sock_path)
    srv = socket.socket(socket.AF_UNIX)
    srv.bind(sock_path); srv.listen(1)
    while True:
        c, _ = srv.accept()
        with c:
            req = json.loads(c.makefile().readline())
            try:
                out, code = run(page, mouse, req["argv"], req.get("stdin", "")), 0
            except SystemExit:
                c.sendall(json.dumps({"out": "OK closed", "code": 0}).encode())
                break
            except Exception as e:
                out, code = f"✗ {type(e).__name__}: {str(e).splitlines()[0][:300]}", 1
            c.sendall(json.dumps({"out": out, "code": code}).encode())
    ctx.close(); os.unlink(sock_path)


def run(page, mouse, argv, stdin):
    a = [x for x in argv if x not in ("--json",)]
    cmd, rest = a[0], a[1:]
    if cmd == "open":
        if rest[0] == "about:blank":   # the fresh tab is still loading its own about:blank: goto would be "interrupted"
            return "✓"
        page.goto(rest[0], wait_until="domcontentloaded", timeout=45000); return "✓ " + page.title()
    if cmd == "close":
        raise SystemExit
    if cmd in ("back", "forward", "reload"):
        getattr(page, {"back": "go_back", "forward": "go_forward", "reload": "reload"}[cmd])(wait_until="domcontentloaded", timeout=45000)
        return "✓"
    if cmd == "wait":
        if rest[:1] == ["--load"]:
            page.wait_for_load_state(rest[1] if rest[1] != "networkidle" else "networkidle", timeout=30000)
        elif rest and rest[0].isdigit():
            page.wait_for_timeout(int(rest[0]))
        else:
            page.wait_for_selector(sel(rest[0]), timeout=30000)
        return "✓"
    if cmd == "get":
        what, s = rest[0], (sel(rest[1]) if len(rest) > 1 else None)
        if what == "url": return page.url
        if what == "title": return page.title()
        if what == "text": return page.inner_text(s or "body")
        if what == "html": return page.inner_html(s or "body")
        if what == "value": return page.input_value(s)
        if what == "attr": return page.get_attribute(sel(rest[2]), rest[1]) or ""
        if what == "count": return str(page.locator(s).count())
        if what == "box":
            b = page.locator(s).first.bounding_box(timeout=5000) or {}
            return json.dumps({"data": b})
    if cmd == "snapshot":
        return page.evaluate(SNAP_JS, False)
    if cmd == "eval":
        r = page.evaluate(rest[0])
        return r if isinstance(r, str) else json.dumps(r, ensure_ascii=False)
    if cmd in ("click", "focus", "scrollintoview", "hover", "check"):
        loc = page.locator(sel(rest[0])).first
        {"click": loc.click, "focus": loc.focus, "scrollintoview": loc.scroll_into_view_if_needed,
         "hover": loc.hover, "check": loc.check}[cmd](timeout=15000)
        return "✓"
    if cmd == "select":
        page.locator(sel(rest[0])).first.select_option(rest[1:]); return "✓"
    if cmd == "press":
        page.keyboard.press(rest[0]); return "✓"
    if cmd == "keyboard" and rest[0] == "type":
        page.keyboard.type(" ".join(rest[1:]), delay=90); return "✓"
    if cmd == "scroll":
        dy = int(rest[1]) if len(rest) > 1 else 600
        page.mouse.wheel(0, -dy if rest[:1] == ["up"] else dy); return "✓"
    if cmd == "screenshot":
        path = rest[0] if rest else os.path.join(ST, "logs", "fox.png")
        page.screenshot(path=path); return path
    if cmd == "set" and rest[0] == "viewport":
        page.set_viewport_size({"width": int(rest[1]), "height": int(rest[2])}); return "✓"
    if cmd == "batch":   # human.py plans: wait / mouse move|down|up|wheel / press / keyboard type
        for st in json.loads(stdin):
            k = st[0]
            if k == "wait": page.wait_for_timeout(int(st[1]))
            elif k == "press": page.keyboard.press(st[1])
            elif k == "keyboard": page.keyboard.type(st[2])
            elif st[1] == "move": mouse[:] = [int(st[2]), int(st[3])]; page.mouse.move(*mouse)
            elif st[1] == "down": page.mouse.down()
            elif st[1] == "up": page.mouse.up()
            elif st[1] == "wheel": page.mouse.wheel(0, int(st[2]))
        return "✓"
    if cmd == "network":   # ruweb's soft-block check reads this; not recorded here
        return json.dumps({"data": {"requests": []}})
    if cmd == "tab":
        return ""
    raise ValueError(f"fox: команда не поддерживается: {' '.join(a)}")


def client(argv):
    stdin = "" if sys.stdin.isatty() or argv[0] != "batch" else sys.stdin.read()
    if not os.path.exists(SOCK):
        if argv[0] != "open":
            print("✗ fox не запущен"); return 1
        os.makedirs(PROFILE, exist_ok=True)
        log = open(os.path.join(ST, "logs", "fox.log"), "a")
        subprocess.Popen([PY, os.path.abspath(__file__), "_serve", PROFILE, SOCK], stdin=subprocess.DEVNULL,
                         stdout=log, stderr=log, start_new_session=True, pass_fds=())
        for _ in range(120):
            if os.path.exists(SOCK): break
            time.sleep(0.5)
        else:
            print("✗ fox не стартовал, см. logs/fox.log"); return 1
    s = socket.socket(socket.AF_UNIX)
    try:
        s.connect(SOCK)
    except OSError:
        os.unlink(SOCK); print("✗ fox не отвечает (сокет устарел)"); return 1
    s.sendall((json.dumps({"argv": argv, "stdin": stdin}) + "\n").encode())
    r = json.loads(s.makefile().read())
    try:
        if r["out"]: print(r["out"], flush=True)
    except BrokenPipeError:   # `| head`
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
    return r["code"]


if __name__ == "__main__":
    if sys.argv[1] == "_serve":
        serve(sys.argv[2], sys.argv[3])
    else:
        sys.exit(client(sys.argv[1:]))
