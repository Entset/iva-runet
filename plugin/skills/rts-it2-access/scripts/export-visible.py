#!/usr/bin/env python3
"""Export the current public RTS list/card through the existing ruweb browser."""
import json
from pathlib import Path
import subprocess
import sys

RUWEB = Path(__file__).resolve().parents[2] / 'ru-web/scripts/ruweb'
JS = r'''(() => {
  if (location.hostname !== 'it2.rts-tender.ru') throw Error('Open it2.rts-tender.ru first');
  const text = document.body.innerText;
  const cells = Array.from(document.querySelectorAll('td,[role=cell]'))
    .filter(e => /ПРОЦЕДУРА/.test(e.innerText));
  const lots = cells.map(e => {
    const raw = e.innerText;
    const links = Array.from(e.querySelectorAll('a[href]'))
      .map(a => ({text:a.innerText.trim(), url:a.href}));
    const lotLinks = links.filter(a => /\/lots\//.test(a.url));
    const money = raw.match(/[\d\s\u00a0]+,\d{2}\s*₽/g) || [];
    return {
      procedure_number:(raw.match(/ПРОЦЕДУРА\s+(\d+)/) || [])[1] || null,
      title:lotLinks.length ? lotLinks[lotLinks.length-1].text : null,
      url:lotLinks.length ? lotLinks[0].url : null,
      displayed_price:money.length ? money[0].trim() : null,
      text:raw, links
    };
  });
  // two card layouts: /v2/trades/<id> and /trades-v2/<id>/lots/<id> (seen 2026-11-02)
  const isCard = /\/(v2\/trades|trades-v2)\/[^/]+/.test(location.pathname);
  if (!lots.length && !(isCard && /\d{10,}/.test(text) && /(Общие|Основные) сведения о процедуре/.test(text)))
    throw Error('No loaded list/card: wait for loading or inspect the browser; no automatic retry');
  return JSON.stringify({captured_at:new Date().toISOString(),url:location.href,
    title:document.title,lots,text,links:Array.from(document.querySelectorAll('a'))
      .filter(a=>a.innerText.trim()).map(a=>({text:a.innerText.trim(),
        url:a.getAttribute('href') ? a.href : null}))});
})()'''

def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python3 export-visible.py OUTPUT.json (open a list/card with ruweb first)')
    result = subprocess.run([str(RUWEB), 'eval', JS], text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    data = json.loads(result.stdout)
    # agent-browser serializes the JavaScript string returned by JSON.stringify.
    if isinstance(data, str):
        data = json.loads(data)
    if not isinstance(data, dict) or 'lots' not in data:
        raise SystemExit('Unexpected browser output; no file written')
    target = Path(sys.argv[1]).expanduser()
    with target.open('x', encoding='utf-8') as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(f'Saved {len(data["lots"])} list items and page text to {target}')

if __name__ == '__main__':
    main()
