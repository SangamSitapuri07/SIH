"""Scenes: intro (chains->crown), market (caravan), damyak (assassination 1206),
polo (Aibak / Lakh Baksh), iltutmish (robe of honour)."""

import math
import random

from lib import *
from scenes1 import hills, ground_strip, dust


def ring(c, x, y, rx, ry, rot, w, col):
    pts = []
    for i in range(21):
        a = TAU * i / 20
        px, py = rx * math.cos(a), ry * math.sin(a)
        pts.append((x + px * math.cos(rot) - py * math.sin(rot),
                    y + px * math.sin(rot) + py * math.cos(rot)))
    c.path(pts, w, col)


def crown(c, x, y, s, col="f2b53a", hi="ffe08a", jewel="d4263c"):
    base = [(-34, 0), (34, 0), (38, -24), (-38, -24)]
    pts = [(-38, -24), (-40, -58), (-20, -38), (0, -66), (20, -38), (40, -58), (38, -24)]
    c.poly([(x + a * s, y + b * s) for a, b in pts], col)
    c.poly([(x + a * s, y + b * s) for a, b in base], col)
    c.rect(x - 34 * s, y - 10 * s, x + 34 * s, y - 6 * s, hi)
    for jx in (-22, 0, 22):
        c.circle(x + jx * s, y - 17 * s, 4.5 * s, jewel)
    for tx, ty in ((-40, -58), (0, -66), (40, -58)):
        c.circle(x + tx * s, y + ty * s, 4 * s, hi)


# ------------------------------------------------------------ INTRO
def intro(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "0f1230"), (0.5, "3a1f4a"), (0.8, "8a3a3a"), (1, "d98a3a")])
    cx, cy = 200, 205 + 7 * math.sin(TAU * t)
    # rotating rays
    for i in range(14):
        a = TAU * i / 14 + TAU * t * 0.5
        w = 0.09
        r = 360
        c.apoly([(cx, cy),
                 (cx + math.cos(a - w) * r, cy + math.sin(a - w) * r),
                 (cx + math.cos(a + w) * r, cy + math.sin(a + w) * r)],
                (255, 214, 120), 0.16)
    c.glow(cx, cy, 170, "ffd070", 0.8)
    # falling chain links
    for j in range(9):
        age = (t + j / 9) % 1
        x = 25 + (j * 47) % 350
        y = -20 + age * 560
        al = 1 - max(0, age - 0.7) / 0.3
        col = mix((120, 120, 135), (30, 25, 40), 1 - al)
        rot = age * TAU * 1.4 + j
        ring(c, x, y, 13, 8, rot, 4, col)
        ring(c, x + math.cos(rot + 1.2) * 14, y + math.sin(rot + 1.2) * 14,
             13, 8, rot + 1.5, 4, col)
    crown(c, cx, cy + 30, 1.9)
    c.glow(cx, cy, 90, "fff0b0", 0.35 + 0.15 * math.sin(TAU * t * 2))
    # freed figure with raised arms at the bottom
    gy = 470
    c.rect(0, gy, W, H, "1a0b18")
    k = math.sin(TAU * t)
    person(c, 200, gy, 1.5, facing=1, col="0a0508", rim="ffcf80", lean=0,
           ra=(158 + 10 * k, 172), la=(-158 - 10 * k, -172), rl=(5, 0), ll=(-5, 0),
           robe=True)
    for hx, hy in (person.rh, person.lh):
        ring(c, hx, hy, 6, 4, 0.4, 2.5, "8a8a9a")
    # sparkles
    rnd = random.Random(2)
    for i in range(26):
        sx, sy = 40 + rnd.random() * 320, 30 + rnd.random() * 380
        tw = max(0, math.sin(TAU * (t + rnd.random())))
        r = 1 + 3 * tw
        c.line((sx - r * 2, sy), (sx + r * 2, sy), 1.2, (255, 235, 170, 255))
        c.line((sx, sy - r * 2), (sx, sy + r * 2), 1.2, (255, 235, 170, 255))
    return c.finish()


# ------------------------------------------------------------ MARKET
def dome_city(c, base_y, col, seed=1, t=0, lit="ffd27a"):
    rnd = random.Random(seed)
    x = -10
    while x < 420:
        w = 30 + rnd.random() * 40
        h = 40 + rnd.random() * 60
        c.rect(x, base_y - h, x + w, base_y + 10, col)
        kind = rnd.random()
        if kind < 0.5:
            c.ellipse(x + w / 2, base_y - h, w / 2, w / 2.4, col)
            c.rect(x + w / 2 - 1, base_y - h - w / 2 - 12, x + w / 2 + 1, base_y - h - w / 2 + 2, col)
        else:
            c.rect(x + w / 2 - 5, base_y - h - 50, x + w / 2 + 5, base_y - h, col)
            c.poly([(x + w / 2 - 6, base_y - h - 50), (x + w / 2, base_y - h - 66),
                    (x + w / 2 + 6, base_y - h - 50)], col)
        for i in range(3):
            if rnd.random() < 0.6:
                tw = 0.6 + 0.4 * math.sin(TAU * (t + rnd.random()))
                wx = x + 6 + i * (w - 12) / 3
                wy0 = base_y - h + 12 + rnd.random() * 10
                wy1 = wy0 + 7 + rnd.random() * 8   # never invert the rect
                c.rect(wx, wy0, wx + 4, wy1, mix((60, 30, 30), hexc(lit), tw))
        x += w + 4 + rnd.random() * 8


def market(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "1c2a5a"), (0.4, "9a4a6a"), (0.65, "f08a4a"), (0.8, "ffd08a")])
    c.glow(300, 300, 150, "ffd090", 0.7)
    dome_city(c, 360, "4a2a4a", seed=4, t=t)
    dome_city(c, 400, "2a1626", seed=9, t=t + 0.3)
    gy = 455
    ground_strip(c, t, W, H, gy, "1d0e14", "4a2530", 1)
    # hanging lanterns
    for i, lx in enumerate((60, 160, 270, 360)):
        sw = math.sin(TAU * t + i) * 5
        c.line((lx, 0), (lx + sw * 0.3, 90 + i * 8), 1.5, "2a1626")
        c.glow(lx + sw, 100 + i * 8, 30, "ffb050", 0.75)
        c.ellipse(lx + sw, 100 + i * 8, 7, 10, "ffd07a")
    p = TAU * t
    # caravan walking right: camel, merchant, boy (tied by rope), second camel
    camel(c, 332, gy + 2, 1.15, p, facing=1)
    # merchant leading (front), boy behind
    person(c, 228, gy + 4, 1.3, facing=1, col="0c0508", rim="ffb070", lean=4,
           ra=(70, 80), la=(-10, 5),
           rl=(26 * math.sin(p), 10 + 14 * max(0, math.sin(p + 1))),
           ll=(-26 * math.sin(p), 10 + 14 * max(0, -math.sin(p + 1))),
           hat="turban", robe=True)
    mh = person.rh
    person(c, 118, gy + 10, 0.95, facing=1, col="0c0508", rim="ffb070", lean=10, head=12,
           ra=(-5, 0), la=(15, 5),
           rl=(22 * math.sin(p + 0.8), 8 + 12 * max(0, math.sin(p + 1.8))),
           ll=(-22 * math.sin(p + 0.8), 8 + 12 * max(0, -math.sin(p + 1.8))),
           cap_col=None)
    bh = person.lh
    # rope
    pts = [(bh[0] + (mh[0] - bh[0]) * u,
            bh[1] + (mh[1] - bh[1]) * u + 9 * math.sin(math.pi * u) + 2 * math.sin(p + u * 6))
           for u in [i / 10 for i in range(11)]]
    c.path(pts, 2, "6a4020")
    camel(c, 26, gy + 6, 0.95, p + 1.5, facing=1)
    # drifting dust
    for j in range(8):
        age = (t + j / 8) % 1
        c.acircle((W + 20) - age * (W + 60), gy - 6 - (j % 3) * 4, 6 + age * 10,
                  (230, 180, 130), 0.35 * (1 - age))
    return c.finish()


# ------------------------------------------------------------ DAMYAK 1206
def damyak(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "05061a"), (0.5, "141a3a"), (0.8, "2a2a4a")])
    stars(c, 60, 11, t, 260)
    c.glow(310, 90, 90, "cfd8ff", 0.5)
    c.circle(310, 90, 26, "eef2ff")
    hills(c, 0, W, H, 330, 18, "10142a", 2, 3, 0.5, 0)
    gy = 470
    c.rect(0, gy - 70, W, H, "0a0c1c")

    # tents
    def tent(x, w, h, col):
        c.poly([(x - w / 2, gy - 60), (x, gy - 60 - h), (x + w / 2, gy - 60)], col)
        c.rect(x - w / 2, gy - 60, x + w / 2, gy - 20, col)

    tent(70, 120, 60, "161a34")
    tent(330, 130, 65, "161a34")
    # Ghori's lit tent in the middle
    flick = 0.8 + 0.2 * math.sin(TAU * t * 5) + 0.1 * math.sin(TAU * t * 8)
    c.glow(240, gy - 70, 150, "ff9a3a", 0.55 * flick)
    c.poly([(170, gy - 62), (240, gy - 160), (310, gy - 62)], "2a1c2a")
    c.rect(170, gy - 62, 310, gy - 18, "2a1c2a")
    c.poly([(212, gy - 18), (240, gy - 100), (268, gy - 18)], (255, 170, 80, 255))
    c.glow(240, gy - 60, 70, "ffd090", 0.7 * flick)
    # assassination progress
    k = t
    sx = 20 + 120 * ease(min(1, k / 0.7))
    strike = 1 if 0.7 < k < 0.86 else 0
    stab = ease(min(1, max(0, (k - 0.66) / 0.1)))
    # Ghori at tent door, startled
    shock = ease(min(1, max(0, (k - 0.72) / 0.1)))
    person(c, 245, gy - 18, 1.4, facing=-1, col="050208", rim="ffcf80",
           lean=-4 * shock, ra=(10, 40), la=(8, 36), rl=(4, 0), ll=(-4, 0),
           hat="helm", robe=True)
    # two assassins creeping from the left
    wlk = TAU * 2 * t
    for i, off in enumerate((0, -64)):
        x = sx + off
        person(c, x, gy - 5 + i * 8, 1.35, facing=1, col="020104", rim="7a8ac0",
               lean=14 + 8 * stab, head=6,
               ra=(95 + 40 * stab if i == 0 else 120, 120 + 10 * stab), la=(-20, -40),
               rl=(24 * math.sin(wlk + i), 8 + 14 * max(0, math.sin(wlk + i + 1))),
               ll=(-24 * math.sin(wlk + i), 8 + 14 * max(0, -math.sin(wlk + i + 1))),
               sword=(100 + 10 * stab, 20), hat="turban")
    # dagger glint
    g = 0.5 + 0.5 * math.sin(TAU * 4 * t)
    c.glow(person.tip[0], person.tip[1], 22, "ffffff", 0.7 * g)
    # campfire
    fx = 130
    c.glow(fx, gy - 8, 70, "ff7a2a", 0.7 * flick)
    for j in range(5):
        age = (t * 2 + j / 5) % 1
        c.acircle(fx + math.sin(age * 9 + j) * 6, gy - 6 - age * 50,
                  5 * (1 - age) + 1.5, (255, 190 - 90 * age, 60), 0.9 * (1 - age))
    c.poly([(fx - 14, gy), (fx, gy - 14), (fx + 14, gy)], "ff9a3a")
    c.rect(fx - 18, gy - 2, fx + 18, gy + 3, "2a1608")
    # strike flash
    if strike:
        fl = math.sin(math.pi * (k - 0.7) / 0.16)
        c.glow(240, gy - 90, 120, "ff4a3a", 0.8 * fl)
        c.glow(240, gy - 90, 60, "ffffff", 0.7 * fl)
    # fade at loop ends (night falls and rises)
    fade = max(max(0, (k - 0.9) / 0.1), max(0, (0.06 - k) / 0.06))
    if fade > 0:
        c.overlay("05061a", min(1, fade))
    return c.finish()


# ------------------------------------------------------------ POLO (Aibak)
def polo(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "2d6fa8"), (0.45, "8fc6e8"), (0.7, "ffe3a8"), (0.85, "f6c46a")])
    c.glow(310, 150, 150, "fff3c0", 0.8)
    c.circle(310, 150, 36, "fffbe6")
    for (cx, cy, w, sp) in [(70, 60, 110, 1), (250, 100, 140, 1), (360, 40, 90, 1)]:
        x = (cx - t * W * sp) % (W + 200) - 100
        c.ellipse(x, cy, w / 2, 11, (255, 255, 255, 255))
        c.ellipse(x + 22, cy - 9, w / 3, 11, (255, 255, 255, 255))
    hills(c, t, W, H, 345, 16, "b9895a", 2, 3, 0.7, 1)
    # palace silhouette with domes (fixed far)
    for x, w, h in ((20, 70, 50), (100, 40, 85), (150, 60, 55)):
        c.rect(x, 345 - h, x + w, 352, "8a5a3a")
        c.ellipse(x + w / 2, 345 - h, w / 2.2, w / 2.6, "8a5a3a")
    gy = 450
    ground_strip(c, t, W, H, gy, "7a8a3a", "5a6a28", 4)
    c.rect(0, gy + 28, W, H, "6a7a30")
    # spectator banners along the top of the field
    for i in range(6):
        bx = (i * 90 - t * W * 2) % (W + 90) - 30
        c.line((bx, gy), (bx, gy - 52), 2.5, "4a2a10")
        c.poly([(bx, gy - 52), (bx + 22 + 3 * math.sin(TAU * t * 2 + i), gy - 46),
                (bx, gy - 36)], "c0392b" if i % 2 else "e8b04b")
    p = TAU * 2 * t
    hx, hs = 150, 1.45
    age = t
    hit = 0.6
    # swing angle of chaugan
    if age < 0.35:
        a = 205
    elif age < 0.35 + 0.25:
        a = 205 - 170 * ease((age - 0.35) / 0.25)
    else:
        a = 35 + 140 * ease(min(1, (age - 0.6) / 0.3))

    def rider(cc, sad, s, pp, f, cy):
        hd, sh = seated(cc, sad, s, f, "140a06", lean=24, rim="ffe0a0", hat="turban",
                        ra=(a - 25, a - 8), la=(30, 50), sword=None)
        hand = person.rh
        L = 78 * s * 0.8
        tip = (hand[0] + math.sin(math.radians(a)) * L * f,
               hand[1] + math.cos(math.radians(a)) * L)
        cc.line(hand, tip, 2.6 * s, "7a4a1a")
        cc.circle(tip[0], tip[1], 3 * s, "4a2a10")
        cc.path([(sh[0] - 6 * s, sh[1] + 2 * s),
                 (sh[0] - 36 * s, sh[1] + 12 * s + 6 * math.sin(pp))], 4 * s, "c0392b")
        polo.tip = tip

    horse(c, hx, gy - 2, hs, p, col="140a06", rim="ffe0a0", rider=rider)
    dust(c, t, hx - 85 * hs * 0.4, gy, 1, col=(210, 170, 110))
    tip = polo.tip
    # ball: rolls in from the right, struck at hit time, flies off in an arc
    if age < hit:
        u = age / hit
        bx = (W + 20) * (1 - u) + (tip[0] + 8) * u
        by = gy - 8
        c.circle(bx, by, 7, "fff6e0")
    else:
        u = (age - hit) / (1 - hit)
        bx = tip[0] + 8 + u * 330
        by = tip[1] - math.sin(u * math.pi) * 170
        c.circle(bx, by, 7, "fff6e0")
        c.glow(bx, by, 22, "ffffff", 0.5 * (1 - u))
    # raining gold (Lakh Baksh)
    rnd = random.Random(7)
    for i in range(22):
        a0 = rnd.random()
        age2 = (t + a0) % 1
        x = 10 + rnd.random() * 380
        y = -10 + age2 * 330
        tw = 0.5 + 0.5 * math.sin(TAU * (t * 3 + a0))
        c.circle(x, y, 3 + 2 * tw, "ffd23a")
        c.circle(x - 1, y - 1, 1.3, "fff6b0")
    return c.finish()


# ------------------------------------------------------------ ILTUTMISH (robe of honour)
def iltutmish(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "10183a"), (0.4, "5a2a5a"), (0.7, "e0703a"), (0.88, "ffc070")])
    stars(c, 30, 21, t, 150)
    c.glow(90, 190, 110, "ffe0a0", 0.6)
    c.circle(90, 190, 28, "ffeec2")
    hills(c, t, W, H, 380, 22, "6a2a40", 1, 2, 0.3, 1)
    # city of Delhi on the right: walls, domes, minars
    base = 392
    c.rect(210, base - 56, 410, base + 20, "2a1226")
    for i in range(10):
        c.rect(212 + i * 20, base - 68, 222 + i * 20, base - 56, "2a1226")
    c.ellipse(310, base - 90, 48, 40, "2a1226")
    c.rect(262, base - 90, 358, base - 56, "2a1226")
    c.rect(306, base - 150, 314, base - 120, "2a1226")
    c.poly([(304, base - 150), (310, base - 166), (316, base - 150)], "2a1226")
    for mx in (240, 380):
        c.rect(mx - 6, base - 130, mx + 6, base - 56, "2a1226")
        c.ellipse(mx, base - 132, 8, 10, "2a1226")
    # gate with warm light
    c.poly([(296, base + 20), (296, base - 20), (310, base - 38), (324, base - 20),
            (324, base + 20)], (255, 190, 100, 255))
    flick = 0.85 + 0.15 * math.sin(TAU * t * 6)
    c.glow(310, base - 10, 70, "ffb050", 0.6 * flick)
    for tx in (285, 335):
        c.circle(tx, base - 24, 3, "ffd070")
        c.glow(tx, base - 24, 22, "ffa040", 0.7 * flick)
    gy = 470
    ground_strip(c, t, W, H, gy, "2a1220", "5a2a38", 4)
    # palms
    for px in (30, 380):
        sway = 3 * math.sin(TAU * t + px)
        c.path([(px, gy), (px + sway, gy - 70), (px + 2 * sway, gy - 120)], 6, "1a0b14")
        for ang in (-160, -130, -100, -70, -40, -10):
            ex = px + 2 * sway + math.cos(math.radians(ang)) * 40
            ey = gy - 120 - math.sin(math.radians(ang)) * 12 + 16
            c.path([(px + 2 * sway, gy - 118), ((px + 2 * sway + ex) / 2, (gy - 118 + ey) / 2 - 7),
                    (ex, ey)], 3.5, "1a0b14")
    p = TAU * 2 * t
    hs = 1.4

    def rider(cc, sad, s, pp, f, cy):
        hd, sh = seated(cc, sad, s, f, "120808", lean=14, rim="ffc880", hat="turban",
                        ra=(176, 150), la=(40, 60))
        hand = person.rh
        # long banner pole with green banner
        top = (hand[0] - 2 * s, hand[1] - 130 * s)
        cc.line((hand[0], hand[1] + 14 * s), top, 2.6 * s, "4a2a10")
        pts_t = [(top[0] - u * 54 * s, top[1] + 4 * s + 6 * math.sin(pp - u * 5) * u * s)
                 for u in [i / 8 for i in range(9)]]
        pts_b = [(x, y + 34 * s) for x, y in pts_t]
        cc.poly(pts_t + pts_b[::-1], "1f8a4a")
        mx, my = (pts_t[4][0] + pts_b[4][0]) / 2, (pts_t[4][1] + pts_b[4][1]) / 2
        cc.circle(mx, my, 6 * s, "ffd23a")
        # robe of honour draped on saddle
        cc.poly([(sad[0] - 12 * s, sad[1] + 4 * s), (sad[0] + 12 * s, sad[1] + 4 * s),
                 (sad[0] + 18 * s, sad[1] + 34 * s + 3 * math.sin(pp)),
                 (sad[0] - 18 * s, sad[1] + 34 * s - 3 * math.sin(pp))], "c9a22a")
        cc.glow(sad[0], sad[1] + 14 * s, 36 * s, "ffd23a", 0.5)

    horse(c, 135, gy - 2, hs, p, col="120808", rim="ffc880", rider=rider)
    dust(c, t, 135 - 85 * hs * 0.4, gy, 1, col=(220, 170, 120))
    return c.finish()
