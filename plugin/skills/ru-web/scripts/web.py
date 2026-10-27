"""Fast tier of ruweb: plain HTTP with a real Chrome TLS/HTTP2 fingerprint (curl_cffi), no browser, no lock — safe in parallel.

  web.py get [--max N] URL...     pages in parallel → text; a page that needs the browser → `NEED_BROWSER <url>: why`, exit 3
  web.py search [-n N] QUERY...   RU search: DuckDuckGo (region ru-ru), Bing ru-RU if DDG fails

Idea from Scrapling's Fetcher tier (curl_cffi first, browser only when needed); ruweb does the escalation.
Runs in its own venv (~/.iva-browser/http/venv), set up by `ruweb setup`.
"""
import base64, html, re, sys
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
from urllib.parse import parse_qs, urlparse

from curl_cffi import requests

HDR = {"Accept-Language": "ru-RU,ru;q=0.9,en;q=0.5"}
BLOCK = re.compile(r"Доступ ограничен|Подозрительная активность|убедиться, что имеем дело|проблема с IP|Anti-?DDoS|"
                   r"не робот|подтвердите, что вы человек|captcha|капч|Access denied|Antibot|Too Many Requests|Forbidden", re.I)
BAD_STATUS = {401, 403, 429, 498, 503}


class Text(HTMLParser):
    SKIP = {"script", "style", "noscript", "svg", "template", "head"}

    def __init__(self):
        super().__init__()
        self.out, self.skip, self.title, self._t = [], 0, "", False

    def handle_starttag(self, tag, a):
        if tag in self.SKIP: self.skip += 1
        if tag == "title": self._t = True
        if tag in ("p", "div", "li", "tr", "br", "h1", "h2", "h3", "h4", "section", "article"): self.out.append("\n")

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skip: self.skip -= 1
        if tag == "title": self._t = False

    def handle_data(self, d):
        if self._t: self.title += d
        elif not self.skip: self.out.append(d)


def text_of(page):
    p = Text()
    p.feed(page)
    t = re.sub(r"[ \t\r\f\v]+", " ", "".join(p.out))
    return " ".join(p.title.split()), re.sub(r"\n\s*\n+", "\n", t).strip()


def fetch(u):
    try:
        r = requests.get(u, impersonate="chrome", headers=HDR, timeout=25, allow_redirects=True)
    except Exception as e:
        return u, None, f"сеть: {str(e)[:120]}"
    title, txt = text_of(r.text)
    if r.status_code in BAD_STATUS or BLOCK.search(title) or (len(txt) < 1500 and BLOCK.search(txt)):
        return u, None, f"антибот ({r.status_code} {title[:60]})".replace(" )", ")")
    if r.status_code >= 400:
        return u, None, f"HTTP {r.status_code}"
    if len(txt) < 400:   # an empty JS shell: the page is drawn by scripts
        return u, None, f"страница рисуется скриптом ({len(txt)} знаков текста)"
    return u, (title, r.url, txt), None


def get(urls, cap):
    need = 0
    with ThreadPoolExecutor(6) as ex:
        for u, ok, why in ex.map(fetch, urls):
            if ok:
                title, final, txt = ok
                print(f"OK {title} | {final}\n{txt[:cap]}{' …' if len(txt) > cap else ''}\n")
            else:
                need = 1
                print(f"NEED_BROWSER {u}: {why}\n")
    return 3 if need else 0


def ddg(q, n):
    r = requests.get("https://html.duckduckgo.com/html/", params={"q": q, "kl": "ru-ru"}, impersonate="chrome", headers=HDR, timeout=20)
    out = []
    for blk in r.text.split('result__body')[1:]:
        m = re.search(r'class="result__a" href="([^"]+)"[^>]*>(.*?)</a>', blk, re.S)
        if not m: continue
        u = html.unescape(m.group(1))
        if "uddg=" in u: u = parse_qs(urlparse(u).query)["uddg"][0]
        if "duckduckgo.com/y.js" in u: continue   # ads
        s = re.search(r'class="result__snippet"[^>]*>(.*?)</a>', blk, re.S)
        out.append((m.group(2), u, s.group(1) if s else ""))
    return out[:n]


def bing(q, n):
    r = requests.get("https://www.bing.com/search", params={"q": q, "setmkt": "ru-RU", "setlang": "ru", "cc": "RU"},
                     impersonate="chrome", headers=HDR, timeout=20)
    out = []
    for blk in r.text.split('<li class="b_algo"')[1:]:
        m = re.search(r'<h2[^>]*><a[^>]*href="([^"]+)"[^>]*>(.*?)</a>', blk, re.S)
        if not m: continue
        u = html.unescape(m.group(1))
        a = parse_qs(urlparse(u).query).get("u", [""])[0]   # bing.com/ck/a?…&u=a1<base64url of the target>
        if a.startswith("a1"): u = base64.urlsafe_b64decode(a[2:] + "=" * (-len(a[2:]) % 4)).decode(errors="replace")
        s = re.search(r"<p[^>]*>(.*?)</p>", blk, re.S)
        out.append((m.group(2), u, s.group(1) if s else ""))
    return out[:n]


def search(q, n):
    clean = lambda s: " ".join(html.unescape(re.sub(r"<.*?>", "", s)).split())
    for name, eng in (("duckduckgo", ddg), ("bing", bing)):
        try:
            res = eng(q, n)
        except Exception:
            res = []
        if res:
            print(f"OK {len(res)} результатов ({name}, регион RU)")
            for i, (t, u, s) in enumerate(res, 1):
                print(f"{i}. {clean(t)}\n   {u}\n   {clean(s)[:300]}")
            return 0
    print("NO_RESULTS: поисковики не ответили — используй web_search")
    return 1


def main(a):
    if len(a) >= 2 and a[0] == "get":
        cap = 20000
        if a[1] == "--max": cap, a = int(a[2]), a[2:]
        return get(a[1:], cap)
    if len(a) >= 2 and a[0] == "search":
        n = 10
        if a[1] == "-n": n, a = int(a[2]), a[2:]
        return search(" ".join(a[1:]), n)
    print(__doc__)
    return 2


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        t, x = text_of("<html><head><title> Т  1 </title><script>var a</script></head><body><p>При&shy;вет</p><style>x</style><li>b</li></body>")
        assert t == "Т 1" and "var" not in x and "Привет" in x.replace("\xad", "") and "b" in x, (t, x)
        assert BLOCK.search("Antibot Challenge Page") and not BLOCK.search("Ситилинк")
        print("selftest OK")
        sys.exit(0)
    sys.exit(main(sys.argv[1:]))
