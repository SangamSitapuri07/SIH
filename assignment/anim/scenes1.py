"""Shared landscape helpers + scenes: razia (horseback), duel (Khalji swords),
mongol (horde across the Indus)."""

import math
import random

from lib import *


# ------------------------------------------------------------------ helpers
def hills(c, t, W, H, base, amp, col, k1, k2, ph, shift_cycles):
    off = t * shift_cycles * W
    pts = [(0, H)]
    for x in range(0, W + 6, 6):
        xx = x + off
        y = base - amp * (0.6 * math.sin(TAU * k1 * xx / W + ph) +
                          0.4 * math.sin(TAU * k2 * xx / W + ph * 1.7))
        pts.append((x, y))
    pts.append((W, H))
    c.poly(pts, col)


def ground_strip(c, t, W, H, gy, col1, col2, cycles, tufts=True):
    c.rect(0, gy, W, H, col1)
    c.rect(0, gy, W, gy + 5, col2)
    if tufts:
        rnd = random.Random(3)
        for i in range(16):
            bx = (rnd.random() * W - t * cycles * W) % W
            by = gy + 14 + rnd.random() * (H - gy - 20)
            L = 8 + rnd.random() * 10
            c.path([(bx, by), (bx - L, by + 2)], 2, col2)


def dust(c, t, hx, gy, f, n=9, spread=130, col=(230, 190, 140), a0=0.55, r0=5):
    for j in range(n):
        age = (t * 2 + j / n) % 1
        x = hx - f * age * spread
        y = gy - 6 - age * 26 - (j % 3) * 3
        c.acircle(x, y, r0 + age * 20, col, a0 * (1 - age))


# ------------------------------------------------------------------ RAZIA
def razia(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "3b1646"), (0.38, "b5362f"), (0.62, "f08a3c"), (0.8, "ffcf7a")])
    c.glow(W * 0.72, H * 0.52, 190, "ffd98a", 0.9)
    c.circle(W * 0.72, H * 0.52, 44, "fff1c2")
    # clouds
    for i, (cx, cy, w) in enumerate([(60, 70, 120), (260, 110, 150), (390, 50, 100)]):
        x = (cx - t * W * 1) % (W + 160) - 80
        c.ellipse(x, cy, w / 2, 9, "e0655a")
        c.ellipse(x + 18, cy - 6, w / 3, 8, "e0655a")
    hills(c, t, W, H, 360, 26, "6b2a3f", 2, 3, 0.4, 1)
    hills(c, t, W, H, 385, 20, "4a1a33", 3, 5, 1.7, 2)
    gy = 440
    ground_strip(c, t, W, H, gy, "2a0f1c", "5a2438", 4)
    p = TAU * 2 * t
    hx, hs = 175, 1.45
    dust(c, t, hx - 85 * hs * 0.4, gy, 1)

    def rider(cc, sad, s, pp, f, cy):
        hd, sh = seated(cc, sad, s * 1.0, f, "140a06", lean=20, rim="ffb870", hat="cap",
                        ra=(168 + 12 * math.sin(pp), 140), la=(30, 60),
                        sword=(150 + 6 * math.sin(pp), 46))
        cape(cc, sh, s, f, pp, "7a1230", length=70, spread=34, amp=9, edge="e8b04b")
        # scarf streamer
        cc.path([(hd[0] - 6 * s, hd[1]),
                 (hd[0] - 30 * s, hd[1] + 4 * s + 4 * math.sin(pp)),
                 (hd[0] - 52 * s, hd[1] + 2 * s + 7 * math.sin(pp - 1))], 3.5 * s, "e8b04b")

    horse(c, hx, gy - 2, hs, p, col="140a06", rim="ffb870", rider=rider,
          mane="140a06", speed_lean=1)
    # sword glint
    g = 0.5 + 0.5 * math.sin(TAU * 2 * t)
    tipx, tipy = person.tip
    c.glow(tipx, tipy, 26, "ffffff", 0.9 * g)
    return c.finish()


# ------------------------------------------------------------------ DUEL (Khalji swords)
def duel(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "0d0a1f"), (0.45, "3a1a3a"), (0.75, "b04a2e"), (1, "e8a04a")])
    stars(c, 40, 5, t, 200)
    c.glow(W * 0.5, 215, 170, "ff9a4a", 0.55)
    c.circle(W * 0.5, 215, 34, "ffd9a0")
    hills(c, 0, W, H, 330, 14, "3a1830", 2, 3, 0.9, 0)
    # silhouetted background battle: small cavalry charging toward each other
    for i in range(3):
        f = 1 if i % 2 == 0 else -1
        bx = (60 + i * 120 + f * (t * 2 % 1) * 60) % (W + 40)
        horse(c, bx, 338, 0.34, TAU * 3 * t + i, col="2a1226", facing=f, rider=None, bob=True)
    gy = 470
    c.rect(0, gy - 25, W, H, "1a0b12")
    c.rect(0, gy - 25, W, gy - 20, "4a2030")
    # strike cycle: attacker swings down at clash moment, recoil
    k = (t * 2) % 1
    swing = ease(min(1, k / 0.45)) if k < 0.45 else 1 - ease((k - 0.45) / 0.55)
    ax, bx = 130 + 14 * swing, 270 - 14 * swing
    # left fighter attacks (sword from high to forward)
    sw_angle_a = 200 - 95 * swing
    person(c, ax, gy, 1.55, facing=1, col="0a0508", rim="ffb070",
           lean=8 + 12 * swing, ra=(185 - 80 * swing, 160 - 70 * swing), la=(-25, -50),
           rl=(30 + 8 * swing, 10), ll=(-30, -22), sword=(sw_angle_a, 52), hat="turban")
    tipA = person.tip
    # right fighter parries with raised sword
    person(c, bx, gy, 1.55, facing=-1, col="0a0508", rim="ffb070",
           lean=6 + 8 * swing, ra=(150 - 25 * swing, 130 - 20 * swing), la=(-25, -45),
           rl=(24, 8), ll=(-26, -20),
           sword=(120 + 40 * (1 - swing) - 20 * swing, 52), hat="helm")
    tipB = person.tip
    # sparks on clash
    if swing > 0.82:
        cx, cy = (tipA[0] + tipB[0]) / 2, (tipA[1] + tipB[1]) / 2
        c.glow(cx, cy, 52, "fff3c0", 0.95)
        rnd = random.Random(int(t * 100))
        for i in range(14):
            a = rnd.random() * TAU
            r = 8 + rnd.random() * 30
            c.line((cx, cy), (cx + math.cos(a) * r, cy + math.sin(a) * r), 1.6, "ffe9a0")
    return c.finish()


# ------------------------------------------------------------------ MONGOLS
def mongol(t, W, H):
    c = Canvas(W, H)
    c.gradient([(0, "2a0f1a"), (0.35, "8a2a24"), (0.6, "e8803a"), (0.78, "f5c06a")])
    c.glow(W * 0.3, 280, 170, "ffd080", 0.7)
    c.circle(W * 0.3, 280, 34, "ffe9b0")
    hills(c, 0, W, H, 330, 14, "5a2230", 2, 3, 0.2, 0)
    # river
    c.rect(0, 340, W, 460, "5a3a50")
    for i in range(14):
        y = 346 + i * 8.5
        for j in range(5):
            x = (j * 95 + i * 31 - t * W * (1 + (i % 2))) % (W + 60) - 30
            c.path([(x, y), (x + 22, y + 1.5)], 1.6,
                   mix((120, 90, 120), (255, 220, 190), 0.4 + 0.3 * (i % 3) / 3))
    c.rect(0, 460, W, H, "2a0f1c")
    # far-bank horde of archers (horses galloping left->right)
    rows = [(335, 0.5, 7), (355, 0.62, 5)]

    def make_rider():
        def rider(cc, sad, s, pp, f, cy):
            hd, sh = seated(cc, sad, s, f, "0c0508", lean=10, hat="helm",
                            ra=(100, 95), la=(95, 92))
            # bow
            bx0, by0 = sh[0] + 14 * s * f, sh[1] + 2 * s
            cc.path([(bx0 + 4 * s * f, by0 - 22 * s), (bx0 + 12 * s * f, by0),
                     (bx0 + 4 * s * f, by0 + 22 * s)], 2 * s, "0c0508")
        return rider

    for gy, sc, n in rows:
        for i in range(n):
            x = ((i * (W + 120) / n) + t * (W + 120) * (1 if gy < 345 else 2) * 0.5) % (W + 120) - 60
            horse(c, x, gy, sc, TAU * 3 * t + i * 1.3, col="0c0508",
                  rider=make_rider(), rim="ff9a60")
    # arrows arcing across the river
    for j in range(7):
        age = (t * 2 + j / 7) % 1
        sx = 20 + j * 55
        ax = sx + age * 200
        ay = 300 - math.sin(age * math.pi) * 150 + age * 80
        dx, dy = 12, math.cos(age * math.pi) * -8 + 6
        c.line((ax - dx, ay - dy), (ax + dx, ay + dy), 1.6, "1c0c10")
    # Delhi's defenders (foreground, near bank) — spears raised and banner
    gy = 470
    for i, x in enumerate((60, 120, 180, 240, 300, 360)):
        sway = math.sin(TAU * t + i)
        person(c, x, gy + (i % 2) * 14, 1.2, facing=1, col="050204", rim="ffb070",
               lean=2, ra=(180, 175), la=(10, 20), rl=(5, 0), ll=(-5, 0), hat="helm")
        hand = person.rh
        c.line((hand[0], hand[1] + 30), (hand[0] + 2 * sway, hand[1] - 90), 2.2, "3a2210")
        c.poly([(hand[0] + 2 * sway, hand[1] - 90), (hand[0] + 6 * sway - 4, hand[1] - 104),
                (hand[0] + 2 * sway + 4, hand[1] - 90)], "c9d2dc")
    # banner on a pole waving
    bx, by = 330, 380
    c.line((bx, by + 90), (bx, by - 20), 3, "3a2210")
    pts_t = [(bx + u * 46, by - 20 + 5 * math.sin(TAU * t * 2 - u * 5) * u)
             for u in [i / 8 for i in range(9)]]
    pts_b = [(x, y + 28) for x, y in pts_t]
    c.poly(pts_t + pts_b[::-1], "1f6b3a")
    return c.finish()
