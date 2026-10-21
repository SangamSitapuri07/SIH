"""Scenes: puppet (throne of whispers), balban (sijda court), tanka (spinning
coin), minar (Qutb Minar), legacy (skyline of what remains)."""

import math
import random

from lib import *
from scenes1 import hills, ground_strip, dust
from scenes2 import crown, ring


# ------------------------------------------------------------ PUPPET YEARS
def puppet(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "120a22"), (0.42, "3a1c40"), (0.72, "7a3446"), (1, "c46a3c")])
    gy = 428
    # back wall + glowing arch niche
    c.rect(0, gy - 240, W, gy, "241228")
    c.glow(200, 300, 190, "ff9a4a", 0.45)
    c.poly([(120, gy), (120, 260), (200, 190), (280, 260), (280, gy)], "321832")
    c.poly([(140, gy), (140, 272), (200, 214), (260, 272), (260, gy)], "3e2038")
    # floor
    c.rect(0, gy, W, H, "180b18")
    c.rect(0, gy, W, gy + 6, "2e1626")
    # dais + steps
    c.rect(150, gy - 16, 250, gy + 6, "2a1424")
    c.rect(162, gy - 32, 238, gy - 16, "321830")
    # throne
    c.rect(178, gy - 32, 222, gy - 8, "241020")
    c.poly([(180, gy - 32), (184, gy - 118), (216, gy - 118), (220, gy - 32)], "2c1428")
    c.poly([(184, gy - 118), (200, gy - 138), (216, gy - 118)], "2c1428")
    # puppet sultan, small and limp
    sway = 3 * math.sin(TAU * t)
    person(c, 200 + sway * 0.4, gy - 8 + 26, 0.72, facing=1, col="1c0c1c", rim="e8a860",
           lean=6 + sway, head=4, ra=(30 + sway * 2, 70), la=(-30 - sway * 2, -70),
           rl=(60, 30), ll=(55, 34), hat="cap")
    hd = person.head
    crown(c, hd[0], hd[1] - 8, 0.42)
    # marionette strings from above the throne to crown / hands / knees
    for i, (tx, ty) in enumerate(((hd[0], hd[1] - 26), (person.rh[0], person.rh[1]),
                                  (person.lh[0], person.lh[1]),
                                  (hd[0] + 18 + sway, hd[1] + 70))):
        sx = 145 + i * 36
        pts = [(sx + u * (tx - sx), u * ty + 4 * math.sin(TAU * t + i + u * 3) * (1 - u))
               for u in (0, 0.33, 0.66, 1)]
        c.path(pts, 1.4, (180, 150, 140, 255))
    # two giant whispering nobles in the foreground (dark, heads inclined)
    person(c, 42, gy + 78, 1.9, facing=1, col="0e0612", rim="c07a48", lean=10, head=8,
           ra=(55, 85), la=(-15, 10), rl=(4, 0), ll=(-6, 2), hat="turban", robe=True)
    person(c, 358, gy + 78, 1.9, facing=-1, col="0e0612", rim="c07a48", lean=10, head=8,
           ra=(55, 85), la=(-15, 10), rl=(-4, 0), ll=(6, 2), hat="turban", robe=True)
    # whisper curls
    for i in range(3):
        u = (t + i / 3) % 1
        xa = 70 + u * 40
        c.path([(xa, 230 - u * 26), (xa + 12, 224 - u * 26 + 5 * math.sin(TAU * (t * 2 + i))),
                (xa + 26, 230 - u * 26)], 1.6, (230, 180, 140, 140))
        xb = 330 - u * 40
        c.path([(xb, 230 - u * 26), (xb - 12, 224 - u * 26 + 5 * math.sin(TAU * (t * 2 + i))),
                (xb - 26, 230 - u * 26)], 1.6, (230, 180, 140, 140))
    # hanging lamps
    for i, lx in enumerate((70, 330)):
        sw = 2.2 * math.sin(TAU * t + i * 2)
        c.line((lx, 0), (lx + sw, 120), 1.5, "241228")
        flick = 0.75 + 0.25 * math.sin(TAU * t * 3 + i)
        c.glow(lx + sw, 132, 36, "ffb050", 0.8 * flick)
        c.ellipse(lx + sw, 132, 7, 11, "ffd07a")
    # dust motes in the glow
    rnd = random.Random(11)
    for i in range(18):
        x = 30 + rnd.random() * 340
        y = 120 + rnd.random() * 300 + 6 * math.sin(TAU * (t + rnd.random()))
        c.acircle(x, y, 1.4, (255, 210, 150), 0.5)
    return c.finish()


# ------------------------------------------------------------ BALBAN (sijda court)
def balban(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "0b1022"), (0.45, "22203c"), (0.75, "4a2c40"), (1, "7a4234")])
    # tall hall: back wall, columns, pointed arches
    c.rect(0, 40, W, 430, "1a1630")
    for i in range(4):
        x = 30 + i * 110
        c.rect(x - 16, 90, x + 16, 430, "242042")
        c.poly([(x - 22, 96), (x, 48), (x + 22, 96)], "242042")
        c.rect(x - 22, 78, x + 22, 96, "2c2850")
    # lamps along the hall
    flick = 0.8 + 0.2 * math.sin(TAU * t * 4)
    for lx in (85, 200, 315):
        c.glow(lx, 150, 60, "ff9a4a", 0.5 * flick)
        c.circle(lx, 150, 7, "ffcf80")
    gy = 430
    c.rect(0, gy, W, H, "140a18")
    c.rect(0, gy, W, gy + 5, "2a1626")
    # dais + throne + the still sultan
    c.rect(130, gy - 26, 270, gy + 4, "221028")
    c.rect(150, gy - 52, 250, gy - 26, "2c1430")
    c.poly([(170, gy - 52), (174, gy - 150), (226, gy - 150), (230, gy - 52)], "241026")
    c.poly([(174, gy - 150), (200, gy - 172), (226, gy - 150)], "241026")
    c.glow(200, gy - 90, 90, "ffb060", 0.5)
    person(c, 200, gy - 26, 1.15, facing=1, col="100612", rim="ffc880", lean=2,
           ra=(20, 35), la=(15, 30), rl=(4, 0), ll=(-4, 0), hat="turban", robe=True)
    hd = person.head
    crown(c, hd[0], hd[1] - 10, 0.5)
    # guards with drawn swords at the sides
    for gx, f in ((46, 1), (354, -1)):
        person(c, gx, gy + 22, 1.35, facing=f, col="0a0510", rim="c88a58", lean=1,
               ra=(170, 165), la=(8, 12), rl=(6, 0), ll=(-6, 0), hat="helm",
               sword=(175, 42))
    # rows of courtiers in sijda — a slow wave of bowing
    for row in range(3):
        for i in range(5):
            x = 55 + i * 72 + (row % 2) * 26
            y = gy + 34 + row * 34
            ph = TAU * t - (i * 0.45 + row * 0.8)
            bow = 0.5 + 0.5 * math.sin(ph)
            lean = 34 + 68 * ease(bow)
            person(c, x, y, 1.05 - row * 0.12,
                   facing=1 if i % 2 == 0 else -1,
                   col="0a0510", rim="a8704c", lean=lean, head=4 + 4 * bow,
                   ra=(18 + 60 * bow, 30 + 70 * bow), la=(12 + 55 * bow, 25 + 65 * bow),
                   rl=(88, 118), ll=(84, 116), hat="turban", robe=True)
    return c.finish()


# ------------------------------------------------------------ TANKA (spinning coin)
def tanka(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "2c1608"), (0.45, "6a3410"), (0.8, "a85c1c"), (1, "d8913a")])
    cx, cy = W / 2, H / 2 - 8
    R = 118
    c.glow(cx, cy, 190, "ffd070", 0.55)
    # spinning about the vertical axis
    k = math.cos(TAU * t)              # face-on at t=0, edge-on at t=0.25
    rx = max(7.0, abs(k) * R)
    # shadow on the ground
    c.ellipse(cx + 8, cy + 150, 86, 12, "341808")
    # coin body + thickness slab
    if abs(k) < 0.14:
        c.rect(cx - 9, cy - R, cx + 9, cy + R, "b8b2a4")
    side = "8e8878" if k < 0 else "b8b2a4"
    c.ellipse(cx, cy, rx + 7, R, side)   # edge
    face = mix("d8d2c2", "f2ead6", 0.5 + 0.5 * k)
    c.ellipse(cx, cy, rx, R - 3, face)
    inner = mix("c0baa8", "e8e0ca", 0.5 + 0.5 * k)
    c.ellipse(cx, cy, rx * 0.86, (R - 3) * 0.86, inner)
    c.ellipse(cx, cy, rx * 0.8, (R - 3) * 0.8, face)
    # central stamp: kufic-like calligraphy, squashed by the spin
    if rx > 18:
        sq = k  # horizontal squash factor
        ink = mix("a89c80", "c8b894", 0.5 + 0.5 * k)
        # beaded inner ring
        for j in range(12):
            a = TAU * j / 12
            c.circle(cx + math.cos(a) * rx * 0.62, cy + math.sin(a) * (R - 3) * 0.62,
                     3.2, ink)
        # calligraphy strokes: varied dashes in three registers
        lines = [
            [(-56, -44, 34), (-14, -44, 22), (16, -44, 40)],
            [(-48, -20, 24), (-16, -20, 44), (36, -20, 18)],
            [(-40, 6, 40), (8, 6, 26)],
            [(-30, 30, 22), (0, 30, 32)],
        ]
        for row in lines:
            for mx, my, mw in row:
                x0 = cx + mx * sq
                x1 = cx + (mx + mw) * sq
                if abs(x1 - x0) > 2:
                    c.rect(min(x0, x1), cy + my, max(x0, x1), cy + my + 9, ink)
        # vertical alif strokes
        for mx in (-52, -22, 20, 46):
            x0 = cx + mx * sq
            if abs(sq) > 0.12:
                c.rect(min(x0, x0 + 7 * sq), cy - 52, max(x0, x0 + 7 * sq), cy + 12, ink)
        # tiny crescent
        if abs(sq) > 0.2:
            c.ellipse(cx + 40 * sq, cy - 66, 11 * abs(sq), 11, ink)
    # rim highlight sweeping
    gl = 0.5 + 0.5 * math.sin(TAU * t * 2 + 1)
    c.acircle(cx - rx * 0.55, cy - R * 0.45, 26 + 10 * gl, (255, 250, 230), 0.5 * gl)
    # spinning mini coins around
    rnd = random.Random(5)
    for i in range(7):
        a0 = rnd.random()
        age = (t + a0) % 1
        x = 40 + rnd.random() * (W - 80)
        y = 20 + age * (H + 60)
        kk = math.cos(TAU * (t * 2 + a0))
        c.ellipse(x, y, max(3.0, abs(kk) * 15), 15, mix("c8b894", "f2e6c8", 0.5 + 0.5 * kk))
    # sparkles
    for i in range(10):
        a0 = rnd.random()
        tw = max(0.0, math.sin(TAU * (t + a0)))
        sx = 30 + rnd.random() * (W - 60)
        sy = 40 + rnd.random() * (H - 80)
        r = 1 + 4 * tw
        c.line((sx - r * 2, sy), (sx + r * 2, sy), 1.2, (255, 240, 190, 255))
        c.line((sx, sy - r * 2), (sx, sy + r * 2), 1.2, (255, 240, 190, 255))
    return c.finish()


# ------------------------------------------------------------ QUTB MINAR
def minar(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "141c40"), (0.3, "3a2c62"), (0.55, "9a4a58"), (0.75, "e0854a"),
                (0.9, "ffc878"), (1, "ffe6b0")])
    stars(c, 26, 8, t, 190)
    c.glow(W * 0.78, 520, 170, "ffd080", 0.75)
    # drifting clouds
    for i, (cx, cy, w) in enumerate([(80, 90, 130), (300, 150, 160), (180, 230, 110),
                                     (360, 60, 100)]):
        x = (cx - t * 46 * (1 + i % 2)) % (W + 170) - 85
        col = mix("6a4a72", "ffb08a", cy / 260)
        c.ellipse(x, cy, w / 2, 10, col)
        c.ellipse(x + 20, cy - 8, w / 3, 9, col)
    # ground
    gy = 552
    c.rect(0, gy, W, H, "2a1a22")
    c.rect(0, gy, W, gy + 5, "4a2c30")
    # ---- the tower (Qutb Minar: deep taper, 5 storeys, balconies, cupola)
    cx = 182
    base_w, top_w, top_y = 150, 64, 118
    floors = [(0.0, 0.28), (0.28, 0.50), (0.50, 0.68), (0.68, 0.83), (0.83, 0.94)]
    tower_col, tower_hi = "3a2430", "6a4250"

    def half_at(u):
        return (base_w + (top_w - base_w) * u) / 2

    for i, (u0, u1) in enumerate(floors):
        y0 = gy - (gy - top_y) * u1
        y1 = gy - (gy - top_y) * u0
        h0, h1 = half_at(u1), half_at(u0)
        c.poly([(cx - h1, y1), (cx - h0, y0), (cx + h0, y0), (cx + h1, y1)],
               tower_col if i % 2 == 0 else tower_hi)
        # vertical fluting (alternating angular / rounded storeys)
        nflu = (3, 4, 3, 4, 3)[i]
        for k in range(1, nflu):
            fx = -1 + 2 * k / nflu
            c.line((cx + fx * h1 * 0.92, y1), (cx + fx * h0 * 0.92, y0), 2.2, "2c1c28")
        # projecting balcony at the top of each storey
        if i < 4:
            by = y0
            c.rect(cx - h0 - 14, by, cx + h0 + 14, by + 12, "241826")
            for bx in range(int(cx - h0 - 10), int(cx + h0 + 10), 10):
                c.rect(bx, by - 10, bx + 4, by, "241826")
            c.rect(cx - h0 - 17, by + 12, cx + h0 + 17, by + 17, "241826")
    # cupola kiosk on top: pillars + dome + finial
    c.rect(cx - 30, top_y - 12, cx + 30, top_y + 2, "241826")
    for px in (-18, -6, 6, 18):
        c.rect(cx + px - 3, top_y - 44, cx + px + 3, top_y - 12, "2c1c28")
    c.rect(cx - 26, top_y - 52, cx + 26, top_y - 42, "241826")
    c.ellipse(cx, top_y - 60, 22, 16, "3a2430")
    c.rect(cx - 2.5, top_y - 92, cx + 2.5, top_y - 72, "241826")
    c.circle(cx, top_y - 95, 4.5, "241826")
    # birds circling the summit
    for i in range(6):
        a = TAU * (t + i / 6)
        bxp = cx + math.cos(a) * (70 + 10 * math.sin(a * 2))
        byp = top_y - 40 + math.sin(a) * 30
        fl = math.sin(TAU * (t * 6 + i)) * 5
        c.line((bxp - 7, byp + fl), (bxp, byp - 2), 1.8, "1c1018")
        c.line((bxp, byp - 2), (bxp + 7, byp + fl), 1.8, "1c1018")
    # pulley: a dressed stone rises up the tower face on a rope, looping
    u = (t * 2) % 1
    rx_at_stone = half_at(1 - u) + 26
    sy = (gy - 60) + (top_y + 50 - (gy - 60)) * ease(u)
    c.line((cx + rx_at_stone, top_y - 20), (cx + rx_at_stone, sy), 1.6, "241826")
    a_stone = min(1, min(u, 1 - u) * 6)
    if a_stone > 0:
        c.apoly([(cx + rx_at_stone - 16, sy - 15), (cx + rx_at_stone + 16, sy - 15),
                 (cx + rx_at_stone + 16, sy + 3), (cx + rx_at_stone - 16, sy + 3)],
                (220, 200, 180), 0.85 * a_stone)
    # slim scaffold hugging the right flank: two poles + rungs + braces
    sx0, sx1 = cx + half_at(0.18) + 46, cx + half_at(0.18) + 64
    c.line((sx0, gy), (sx0, top_y + 120), 2.6, "2c1c24")
    c.line((sx1, gy), (sx1, top_y + 130), 2.6, "2c1c24")
    for hy in range(int(top_y + 130), int(gy), 38):
        c.line((sx0 - 3, hy), (sx1 + 3, hy), 2, "2c1c24")
    for hy in range(int(top_y + 140), int(gy) - 40, 76):
        c.line((sx0, hy), (sx1, hy + 34), 1.8, "2c1c24")
        c.line((sx1, hy), (sx0, hy + 34), 1.8, "2c1c24")
    return c.finish()


# ------------------------------------------------------------ LEGACY (skyline)
def legacy(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "241238"), (0.35, "6a2a4a"), (0.58, "c25a34"), (0.78, "ff9a4a"),
                (1, "ffd9a0")])
    c.glow(W * 0.5, 430, 190, "ffd080", 0.8)
    c.circle(W * 0.5, 430, 40, "fff0c0")
    # clouds, slowly drifting
    for i, (cx, cy, w) in enumerate([(70, 80, 130), (280, 120, 150), (390, 60, 100),
                                     (160, 180, 110)]):
        x = (cx - t * 40 * (1 + i % 2)) % (W + 170) - 85
        col = mix("8a4a62", "ffc090", cy / 200)
        c.ellipse(x, cy, w / 2, 10, col)
        c.ellipse(x + 22, cy - 8, w / 3, 9, col)
    # far skyline layer (slow parallax)
    off = t * 14
    for i, (dx, w, h) in enumerate(((20, 46, 60), (90, 30, 96), (150, 56, 54),
                                    (240, 34, 84), (310, 60, 58), (380, 28, 92))):
        x = dx - off % 60
        base = 402
        c.rect(x, base - h, x + w, base + 10, "5a2438")
        if h > 80:   # minaret
            c.ellipse(x + w / 2, base - h, w / 2.4, 10, "5a2438")
            c.rect(x + w / 2 - 2, base - h - 16, x + w / 2 + 2, base - h, "5a2438")
        else:        # dome
            c.ellipse(x + w / 2, base - h, w / 2, w / 2.6, "5a2438")
    # main mosque screen: central pointed arch + side arches (Quwwat-ul-Islam)
    base = 448
    mid = "3a1830"
    c.rect(20, base - 120, 380, base + 10, mid)
    for i in range(9):
        c.rect(26 + i * 40, base - 132, 46 + i * 40, base - 120, mid)
    # central arch
    c.poly([(150, base + 10), (150, 330), (200, 268), (250, 330), (250, base + 10)],
           "1c0c1c")
    c.poly([(162, base + 10), (162, 338), (200, 290), (238, 338), (238, base + 10)],
           "2e1428")
    # side arches
    for ax in (70, 330):
        c.poly([(ax - 34, base + 10), (ax - 34, 372), (ax, 336), (ax + 34, 372),
                (ax + 34, base + 10)], "1c0c1c")
    # the great minaret beside it + domes
    mx = 368
    c.rect(mx - 22, base - 260, mx + 22, base + 10, mid)
    for uy, hw in ((0, 22), (1, 18), (2, 14)):
        y = base - 100 - uy * 80
        c.rect(mx - hw - 7, y, mx + hw + 7, y + 9, "2a1226")
        for bx in range(int(mx - hw - 4), int(mx + hw + 4), 8):
            c.rect(bx, y - 7, bx + 3, y, "2a1226")
    c.ellipse(mx, base - 262, 14, 12, mid)
    c.rect(mx - 2, base - 286, mx + 2, base - 272, mid)
    for dx2, r in ((108, 30), (272, 36)):
        c.rect(dx2 - r, base - 150, dx2 + r, base + 10, mid)
        c.ellipse(dx2, base - 150, r, r * 0.78, mid)
        c.rect(dx2 - 2.5, base - 150 - r - 12, dx2 + 2.5, base - 150 - r + 2, mid)
    # warm lamps in the arches
    flick = 0.75 + 0.25 * math.sin(TAU * t * 3)
    for lx in (70, 200, 330):
        c.glow(lx, base - 40, 34, "ffb050", 0.6 * flick)
        c.circle(lx, base - 40, 5, "ffd07a")
    # foreground ground + grass
    gy = 448
    c.rect(0, gy, W, H, "241018")
    c.rect(0, gy, W, gy + 5, "4a2028")
    rnd = random.Random(9)
    for i in range(14):
        bx = (rnd.random() * W - t * 60) % W
        by = gy + 18 + rnd.random() * (H - gy - 26)
        L = 9 + rnd.random() * 11
        c.path([(bx, by), (bx - L, by + 2)], 2, "4a2028")
    # birds gliding home
    for i in range(7):
        u = (t + i / 7) % 1
        bxp = -30 + u * (W + 60)
        byp = 120 + 40 * math.sin(TAU * (u + i * 0.13)) + i * 9
        fl = math.sin(TAU * (t * 5 + i)) * 5
        c.line((bxp - 8, byp + fl), (bxp, byp - 2), 1.8, "1c0c18")
        c.line((bxp, byp - 2), (bxp + 8, byp + fl), 1.8, "1c0c18")
    return c.finish()


# ------------------------------------------------------------ TEDDY (thank you)
import os as _os

_FONT_BOLD = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)),
                           "..", "assets", "TNRBold.ttf")
_FONT_DISP = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)),
                           "..", "assets", "Bernard.ttf")


def _heart(c, x, y, s, col, alpha=1.0):
    pts = []
    for i in range(13):
        a = TAU * i / 12
        hx = 16 * math.sin(a) ** 3
        hy = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a))
        pts.append((x + hx * s, y + hy * s))
    if alpha >= 1:
        c.poly(pts, col)
    else:
        c.apoly(pts, col, alpha)


def teddy(t, W, H):
    """A plush teddy bear waving and saying 'Thank you mates!'"""
    c = Canvas(W, H)
    c.gradient([(0, "ffe3b0"), (0.55, "f7b06a"), (1, "e07a4a")])
    c.glow(200, 240, 230, "ffe8b8", 0.55)
    # party bunting across the top corners
    for side in (0, 1):
        x0, x1 = (-20, 190) if side == 0 else (210, 420)
        y0, y1 = (8, 52) if side == 0 else (52, 8)
        pts = [(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u + 14 * math.sin(math.pi * u))
               for u in [i / 6 for i in range(7)]]
        c.path(pts, 2.4, "8a4a28")
        for i in range(6):
            u = i / 6
            fx = x0 + (x1 - x0) * (u + 0.08)
            fy = y0 + (y1 - y0) * (u + 0.08) + 14 * math.sin(math.pi * (u + 0.08))
            col = ("d4404c" if i % 2 == 0 else "f2b53a") if side == 0 else ("2e8b57" if i % 2 == 0 else "e8895a")
            c.poly([(fx - 8, fy + 1), (fx + 8, fy + 1), (fx, fy + 20)], col)
    # falling confetti
    rnd = random.Random(21)
    cols = ["d4404c", "f2b53a", "2e8b57", "4a7ac8", "e8895a", "b04ac8"]
    for i in range(24):
        a0 = rnd.random()
        x = rnd.random() * W
        y = ((t + a0) % 1) * (H + 50) - 25
        rot = TAU * (t * 2 + a0)
        w, h = 3.2, 6.5
        ca, sa = math.cos(rot), math.sin(rot)
        col = cols[i % len(cols)]
        c.poly([(x + w * ca - h * sa, y + w * sa + h * ca),
                (x - w * ca - h * sa, y - w * sa + h * ca),
                (x - w * ca + h * sa, y - w * sa - h * ca),
                (x + w * ca + h * sa, y + w * sa - h * ca)], col)
    # rising hearts
    for i in range(5):
        a0 = rnd.random()
        u = (t + a0) % 1
        hx = (46 if i % 2 == 0 else W - 46) + (rnd.random() - 0.5) * 60
        hy = H + 30 - u * (H * 0.72)
        al = min(1, min(u, 1 - u) * 4) * 0.75
        _heart(c, hx, hy, 0.7 + 0.3 * math.sin(TAU * (t + a0)), "c8324a", al)

    # ---------------- teddy bear ----------------
    bob = 4.0 * math.sin(TAU * t)                 # body bounce
    hbob = bob * 1.6                              # head bob
    FUR = "8a5228"        # main brown
    FUR_D = "6e3c1c"      # shaded brown
    FUR_L = "b06a34"      # highlight brown
    TAN = "e0b078"        # muzzle / belly / pads
    GY = 488
    cx = 200

    def fluff(x, y, rx, ry, n, r, col, seed):
        rr = random.Random(seed)
        for i in range(n):
            a = TAU * (i / n + 0.02 * rr.random())
            fx = x + math.cos(a) * rx
            fy = y + math.sin(a) * ry
            c.circle(fx, fy, r * (0.85 + 0.3 * rr.random()), col)

    # shadow under the bear
    c.ellipse(cx + 6, GY + 6, 118, 18, "b06030")
    # hind feet (in front of body)
    for fx in (cx - 66, cx + 66):
        c.ellipse(fx, GY - 16, 42, 26, FUR)
        fluff(fx, GY - 16, 40, 25, 12, 6, FUR_D, 7)
        c.ellipse(fx, GY - 14, 24, 15, TAN)
    # body
    c.ellipse(cx, GY - 92 + bob, 96, 88, FUR)
    fluff(cx, GY - 92 + bob, 94, 86, 26, 8, FUR_D, 3)
    c.ellipse(cx, GY - 86 + bob, 58, 52, TAN)
    c.ellipse(cx - 26, GY - 120 + bob, 40, 30, FUR_L)   # chest sheen
    # left arm (viewer left) hanging down
    c.line((cx - 82, GY - 118 + bob), (cx - 108, GY - 52 + bob), 34, FUR)
    c.circle(cx - 82, GY - 118 + bob, 18, FUR)
    c.circle(cx - 108, GY - 52 + bob, 19, FUR)
    c.ellipse(cx - 110, GY - 48 + bob, 11, 9, TAN)
    # right arm waving (paw clear of the head silhouette)
    wa = math.radians(-52 + 16 * math.sin(TAU * 2 * t))
    sh = (cx + 82, GY - 118 + bob)
    paw = (sh[0] + math.cos(wa) * 86, sh[1] + math.sin(wa) * 86)
    c.line(sh, paw, 34, FUR)
    c.circle(sh[0], sh[1], 18, FUR)
    c.circle(paw[0], paw[1], 20, FUR)
    c.ellipse(paw[0] + math.cos(wa) * 5, paw[1] + math.sin(wa) * 5, 11, 9, TAN)
    # head
    hy = 252 + hbob
    c.ellipse(cx, hy, 88, 80, FUR)
    fluff(cx, hy, 86, 78, 22, 8, FUR_D, 5)
    # ears
    for ex in (cx - 62, cx + 62):
        c.circle(ex, hy - 56, 34, FUR)
        c.circle(ex, hy - 56, 22, FUR_D)
        c.circle(ex, hy - 56, 15, TAN)
    c.ellipse(cx - 32, hy - 30, 36, 26, FUR_L)          # forehead sheen
    # muzzle
    c.ellipse(cx, hy + 42, 52, 38, TAN)
    # eyes (button eyes with glint, blinking)
    blink = (t % 0.5) > 0.44
    for ex in (cx - 34, cx + 34):
        if blink:
            c.line((ex - 11, hy - 8), (ex + 11, hy - 8), 4.5, FUR_D)
        else:
            c.circle(ex, hy - 8, 12, "241208")
            c.circle(ex - 3.5, hy - 11, 4.2, "ffffff")
            c.circle(ex + 3, hy - 4, 1.8, "ffffff")
    # rosy cheeks
    c.acircle(cx - 58, hy + 30, 15, (220, 110, 110), 0.35)
    c.acircle(cx + 58, hy + 30, 15, (220, 110, 110), 0.35)
    # nose + shine
    c.ellipse(cx, hy + 26, 17, 12, "3a1c0c")
    c.ellipse(cx - 5, hy + 22, 5, 3.5, "6a4428")
    # mouth talking
    o = 0.5 + 0.5 * math.sin(TAU * 6 * t)
    c.ellipse(cx, hy + 52, 9 + 5 * o, 3 + 9 * o, "3a1c0c")
    c.path([(cx - 22, hy + 44), (cx - 12, hy + 50 + 3 * o), (cx, hy + 46)], 3, "5a2c14")
    c.path([(cx + 22, hy + 44), (cx + 12, hy + 50 + 3 * o), (cx, hy + 46)], 3, "5a2c14")

    # ---------------- speech bubble ----------------
    by = 3.5 * math.sin(TAU * 2 * t)
    bx0, bx1, by0, by1 = 52, 348, 62 + by, 152 + by
    c.rrect(bx0 - 5, by0 - 5, bx1 + 5, by1 + 5, 26, "3a1c0c")
    c.rrect(bx0, by0, bx1, by1, 22, "fffdf4")
    # tail toward the bear's head
    c.poly([(196, by1 - 4), (236, by1 - 4), (222, by1 + 46 + hbob * 0.4)], "3a1c0c")
    c.poly([(204, by1 - 6), (228, by1 - 6), (218, by1 + 38 + hbob * 0.4)], "fffdf4")
    c.text(200, 102 + by, "Thank you mates!", _FONT_DISP if _os.path.exists(_FONT_DISP) else _FONT_BOLD,
           30, "4a2210")
    # sparkle stars around the bear
    for i in range(8):
        a0 = rnd.random()
        tw = max(0.0, math.sin(TAU * (t + a0)))
        sx = 30 + rnd.random() * (W - 60)
        sy = 180 + rnd.random() * (H - 230)
        r = 1.2 + 4 * tw
        c.line((sx - r * 2, sy), (sx + r * 2, sy), 1.3, (255, 245, 210, 255))
        c.line((sx, sy - r * 2), (sx, sy + r * 2), 1.3, (255, 245, 210, 255))
    return c.finish()
