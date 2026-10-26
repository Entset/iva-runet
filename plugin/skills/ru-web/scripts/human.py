#!/usr/bin/env python3
"""Plans human-like input as one agent-browser `batch` JSON (one CLI call per action, ~1.3 s each otherwise).

  human.py move  CX CY X Y              -> path from cursor to point
  human.py click CX CY BX BY BW BH VW VH MISS -> approach, pause, [miss], click; 2nd line: "fx fy mx my"
  human.py type  TEXT                   -> word-paced keystrokes with occasional typo + Backspace
  human.py read  LVL CX CY VW VH        -> wheel impulses, reading pauses, mouse drift; 2nd line: "fx fy"
Line 1 is the JSON array for `agent-browser batch`; line 2 (if any) is state for the caller.
"""
import json, math, random, sys

R = random.SystemRandom()
cmds = []


def wait(lo, hi):
    cmds.append(["wait", str(int(R.uniform(lo, hi)))])


def path(x0, y0, x1, y1):
    """Quadratic curve with a random bend; cosine easing = slow start, fast middle, slow finish."""
    dx, dy = x1 - x0, y1 - y0
    dist = math.hypot(dx, dy)
    if dist < 2:
        return
    n = R.randint(8, 20) if dist > 60 else R.randint(4, 7)
    off = R.uniform(0.08, 0.28) * dist * R.choice((-1, 1))
    cx, cy = (x0 + x1) / 2 - dy / dist * off, (y0 + y1) / 2 + dx / dist * off
    for i in range(1, n + 1):
        e = (1 - math.cos(math.pi * i / n)) / 2
        x = (1 - e) ** 2 * x0 + 2 * (1 - e) * e * cx + e ** 2 * x1
        y = (1 - e) ** 2 * y0 + 2 * (1 - e) * e * cy + e ** 2 * y1
        if i < n:
            x, y = x + R.uniform(-1, 1), y + R.uniform(-1, 1)
        cmds.append(["mouse", "move", str(int(x)), str(int(y))])
        wait(12, 40)


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


# Adjacent keys for typos (same row, either side).
ROWS = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm", "йцукенгшщзхъ", "фывапролджэ", "ячсмитьбю"]


def neighbour(c):
    for row in ROWS:
        i = row.find(c.lower())
        if i >= 0:
            j = clamp(i + R.choice((-1, 1)), 0, len(row) - 1)
            n = row[j] if j != i else row[i - 1 if i else i + 1]
            return n.upper() if c.isupper() else n
    return None


def press(key):
    cmds.append(["press", key])


def type_text(text):
    next_typo = R.randint(25, 40)
    for k, c in enumerate(text):
        if c == " ":
            wait(300, 900)                      # word boundary
        elif c.isupper():
            wait(90, 220)                       # reaching for Shift
        next_typo -= 1
        n = neighbour(c) if next_typo <= 0 else None
        if n:
            next_typo = R.randint(25, 40)
            cmds.append(["keyboard", "type", n])
            wait(120, 350)                      # notice the mistake
            if R.random() < 0.35 and k + 1 < len(text) and text[k + 1] != " ":
                cmds.append(["keyboard", "type", text[k + 1]])   # one more key before noticing
                wait(60, 140)
                press("Backspace"); wait(60, 140)
            press("Backspace"); wait(80, 200)
        cmds.append(["keyboard", "type", c])
        slow = 1.0 if c.isalnum() or c == " " else R.uniform(1.3, 1.5)
        wait(40 * slow, 90 * slow)


def main():
    op, a = sys.argv[1], sys.argv[2:]
    extra = None
    if op == "move":
        cx, cy, x, y = map(float, a)
        path(cx, cy, x, y)
    elif op == "click":
        cx, cy, bx, by, bw, bh, vw, vh = map(float, a[:8])
        miss = a[8] == "1"
        # click point 10–40 % of the size away from the centre, never the edge
        tx = clamp(bx + bw / 2 + R.choice((-1, 1)) * bw * R.uniform(0.1, 0.4), bx + 2, bx + bw - 2)
        ty = clamp(by + bh / 2 + R.choice((-1, 1)) * bh * R.uniform(0.1, 0.4), by + 2, by + bh - 2)
        tx, ty = clamp(tx, 2, vw - 2), clamp(ty, 2, vh - 2)
        ang, r = R.uniform(0, 2 * math.pi), R.uniform(20, 60)
        ax, ay = clamp(tx + math.cos(ang) * r, 2, vw - 2), clamp(ty + math.sin(ang) * r, 2, vh - 2)
        side, d = R.randint(0, 3), R.uniform(5, 15)
        mx, my = [(bx - d, by + R.uniform(0, bh)), (bx + bw + d, by + R.uniform(0, bh)),
                  (bx + R.uniform(0, bw), by - d), (bx + R.uniform(0, bw), by + bh + d)][side]
        mx, my = clamp(mx, 2, vw - 2), clamp(my, 2, vh - 2)
        path(cx, cy, ax, ay)
        wait(80, 250)
        if miss:
            path(ax, ay, mx, my)
            cmds.extend([["mouse", "down"], ["mouse", "up"]])
            wait(120, 300)
            path(mx, my, tx, ty)
        else:
            path(ax, ay, tx, ty)
        cmds.append(["mouse", "down"]); wait(40, 120); cmds.append(["mouse", "up"])
        wait(100, 300)
        extra = f"{int(tx)} {int(ty)} {int(mx)} {int(my)}"
    elif op == "type":
        type_text(" ".join(a))
    elif op == "read":
        lvl = a[0]
        cx, cy, vw, vh = map(float, a[1:5])
        screens = R.uniform(3, 5) if lvl == "strict" else R.uniform(1, 2.5)
        budget, done = screens * vh, 0
        stops = sorted(R.uniform(0.15, 0.95) * budget for _ in range(R.randint(2, 4) if lvl == "strict" else 1))
        wait(800, 2500)                          # look at the top first
        while done < budget:
            for _ in range(R.randint(2, 5)):     # one flick = several wheel notches with inertia
                step = R.randint(120, 400)
                cmds.append(["mouse", "wheel", str(step)]); done += step
                wait(30, 120)
            if R.random() < 0.5:                 # cursor drifts while reading
                nx, ny = clamp(cx + R.uniform(-250, 250), 20, vw - 20), clamp(cy + R.uniform(-150, 150), 20, vh - 20)
                path(cx, cy, nx, ny); cx, cy = nx, ny
            while stops and done >= stops[0]:
                stops.pop(0); wait(800, 2500)    # reading a paragraph
            wait(200, 700)
        if R.random() < 0.2:                     # scroll back a bit and re-read
            back = int(done * R.uniform(0.1, 0.2))
            while back > 0:
                step = min(back, R.randint(120, 300))
                cmds.append(["mouse", "wheel", str(-step)]); back -= step
                wait(30, 120)
            wait(800, 2500)
        extra = f"{int(cx)} {int(cy)}"
    print(json.dumps(cmds, ensure_ascii=False))
    if extra:
        print(extra)


if __name__ == "__main__":
    main()
