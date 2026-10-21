"""Silhouette animation drawing toolkit (supersampled PIL canvas).

Everything draws on a Canvas at SS x resolution and downsamples on finish().
Figures are built from capsule/polygon ops so each one can be painted twice:
a rim-light pass offset up-and-back, then the solid silhouette on top.

Angle convention for every limb / weapon (degrees):
    0   = straight down
    90  = horizontal, toward `facing`
    180 = straight up
    >180 or <0 wraps (e.g. 205 = up and behind)
"""

import math
import random

from PIL import Image, ImageDraw

TAU = math.tau
SS = 3  # supersample factor


# ------------------------------------------------------------------ helpers
def clamp(v, a=0.0, b=1.0):
    return a if v < a else (b if v > b else v)


def hexc(c):
    """'#rrggbb' | (r,g,b) | (r,g,b,a) -> (r,g,b,a)."""
    if isinstance(c, str):
        s = c.lstrip("#")
        return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)
    if len(c) == 3:
        return (int(c[0]), int(c[1]), int(c[2]), 255)
    return (int(c[0]), int(c[1]), int(c[2]), int(c[3]))


def mix(a, b, t):
    t = clamp(t)
    a, b = hexc(a), hexc(b)
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))


def ease(u):
    u = clamp(u)
    return u * u * (3 - 2 * u)


_FONT_CACHE = {}


def _font(path, px):
    key = (path, px)
    if key not in _FONT_CACHE:
        from PIL import ImageFont
        _FONT_CACHE[key] = ImageFont.truetype(path, px)
    return _FONT_CACHE[key]


# ------------------------------------------------------------------ canvas
class Canvas:
    def __init__(self, W, H, ss=SS):
        self.W, self.H, self.ss = W, H, ss
        self.img = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 255))
        self.d = ImageDraw.Draw(self.img)

    # ---- low-level -------------------------------------------------
    def _pts(self, pts):
        return [(x * self.ss, y * self.ss) for x, y in pts]

    def _composite(self, patch, x0, y0):
        """Alpha-composite an RGBA patch at pixel dest (x0, y0)."""
        W, H = self.img.size
        pw, ph = patch.size
        cx0, cy0 = max(0, x0), max(0, y0)
        cx1, cy1 = min(W, x0 + pw), min(H, y0 + ph)
        if cx1 <= cx0 or cy1 <= cy0:
            return
        patch = patch.crop((cx0 - x0, cy0 - y0, cx1 - x0, cy1 - y0))
        base = self.img.crop((cx0, cy0, cx1, cy1))
        self.img.paste(Image.alpha_composite(base, patch), (cx0, cy0))
        self.d = ImageDraw.Draw(self.img)

    # ---- opaque primitives ----------------------------------------
    def rect(self, x0, y0, x1, y1, col):
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        self.d.rectangle([x0 * self.ss, y0 * self.ss, x1 * self.ss, y1 * self.ss],
                         fill=hexc(col))

    def rrect(self, x0, y0, x1, y1, r, col):
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        self.d.rounded_rectangle([x0 * self.ss, y0 * self.ss, x1 * self.ss, y1 * self.ss],
                                 radius=max(1, int(r * self.ss)), fill=hexc(col))

    def text(self, x, y, s, font, size, col, anchor="mm"):
        """Draw text; `font` is a ttf path, `size` in canvas units."""
        f = _font(font, max(4, int(size * self.ss)))
        self.d.text((x * self.ss, y * self.ss), s, font=f, fill=hexc(col), anchor=anchor)

    def poly(self, pts, col):
        self.d.polygon(self._pts(pts), fill=hexc(col))

    def circle(self, x, y, r, col):
        s = self.ss
        self.d.ellipse([(x - r) * s, (y - r) * s, (x + r) * s, (y + r) * s], fill=hexc(col))

    def ellipse(self, x, y, rx, ry, col):
        s = self.ss
        self.d.ellipse([(x - rx) * s, (y - ry) * s, (x + rx) * s, (y + ry) * s], fill=hexc(col))

    def line(self, p0, p1, w, col):
        s = self.ss
        self.d.line([p0[0] * s, p0[1] * s, p1[0] * s, p1[1] * s],
                    fill=hexc(col), width=max(1, int(round(w * s))))

    def path(self, pts, w, col):
        if len(pts) < 2:
            return
        s = self.ss
        self.d.line(self._pts(pts), fill=hexc(col),
                    width=max(1, int(round(w * s))), joint="curve")

    # ---- alpha compositing ----------------------------------------
    def acircle(self, x, y, r, color, alpha):
        r = max(r, 0.5)
        w = int(2 * r * self.ss) + 2
        patch = Image.new("RGBA", (w, w), (0, 0, 0, 0))
        ImageDraw.Draw(patch).ellipse([0, 0, w - 1, w - 1],
                                      fill=hexc(color)[:3] + (int(255 * clamp(alpha)),))
        self._composite(patch, int((x - r) * self.ss) - 1, int((y - r) * self.ss) - 1)

    def apoly(self, pts, color, alpha):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        x0, y0 = int(min(xs) * self.ss) - 2, int(min(ys) * self.ss) - 2
        x1, y1 = int(max(xs) * self.ss) + 3, int(max(ys) * self.ss) + 3
        patch = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
        ImageDraw.Draw(patch).polygon(
            [((px * self.ss) - x0, (py * self.ss) - y0) for px, py in pts],
            fill=hexc(color)[:3] + (int(255 * clamp(alpha)),))
        self._composite(patch, x0, y0)

    def glow(self, x, y, r, color, alpha):
        """Soft radial glow (squarish falloff, smoothly dithered)."""
        r = max(r, 1.0)
        n = 32
        mask = Image.new("L", (n, n), 0)
        px = mask.load()
        c0 = n / 2.0
        for yy in range(n):
            dy = (yy + 0.5 - c0) / c0
            for xx in range(n):
                dx = (xx + 0.5 - c0) / c0
                d2 = dx * dx + dy * dy
                if d2 < 1.0:
                    px[xx, yy] = int(255 * clamp(alpha) * (1.0 - d2) ** 2)
        w = int(2 * r * self.ss) + 2
        mask = mask.resize((w, w), Image.BILINEAR)
        patch = Image.new("RGBA", (w, w), hexc(color)[:3] + (255,))
        patch.putalpha(mask)
        self._composite(patch, int((x - r) * self.ss) - 1, int((y - r) * self.ss) - 1)

    def overlay(self, color, alpha):
        w, h = self.img.size
        patch = Image.new("RGBA", (w, h), hexc(color)[:3] + (int(255 * clamp(alpha)),))
        self._composite(patch, 0, 0)

    def gradient(self, stops):
        """Vertical gradient; stops = [(pos 0..1, color), ...] in any order."""
        stops = sorted(((p, hexc(c)) for p, c in stops), key=lambda s: s[0])
        H = self.H * self.ss
        col = Image.new("RGBA", (1, H))
        px = col.load()
        for y in range(H):
            t = y / (H - 1) if H > 1 else 0.0
            if t <= stops[0][0]:
                c = stops[0][1]
            elif t >= stops[-1][0]:
                c = stops[-1][1]
            else:
                c = stops[-1][1]
                for i in range(len(stops) - 1):
                    p0, c0 = stops[i]
                    p1, c1 = stops[i + 1]
                    if p0 <= t <= p1:
                        c = mix(c0, c1, (t - p0) / (p1 - p0) if p1 > p0 else 0.0)
                        break
            px[0, y] = c
        self.img = col.resize((self.W * self.ss, H), Image.BILINEAR)
        self.d = ImageDraw.Draw(self.img)

    def finish(self):
        return self.img.convert("RGB").resize((self.W, self.H), Image.LANCZOS)


# ------------------------------------------------------------------ op painter
def _P(pts, col):
    return ("poly", pts, col)


def _L(p0, p1, w, col):
    return ("line", p0, p1, w, col)


def _C(x, y, r, col):
    return ("circle", x, y, r, col)


def _E(x, y, rx, ry, col):
    return ("ellipse", x, y, rx, ry, col)


def paint(c, ops, dx=0.0, dy=0.0, col=None):
    for op in ops:
        if op[0] == "poly":
            c.poly([(px + dx, py + dy) for px, py in op[1]], col or op[2])
        elif op[0] == "line":
            (x0, y0), (x1, y1), w = op[1], op[2], op[3]
            c.line((x0 + dx, y0 + dy), (x1 + dx, y1 + dy), w, col or op[4])
        elif op[0] == "circle":
            c.circle(op[1] + dx, op[2] + dy, op[3], col or op[4])
        elif op[0] == "ellipse":
            c.ellipse(op[1] + dx, op[2] + dy, op[3], op[4], col or op[5])


def paint_rimmed(c, ops, s, facing, rim):
    """Rim-light pass up-and-back, then the solid pass."""
    if rim:
        paint(c, ops, dx=-facing * 1.9 * s, dy=-1.5 * s, col=hexc(rim))
    paint(c, ops)


# ------------------------------------------------------------------ person
def person(c, x, y, s=1.0, facing=1, col="0a0508", rim=None, lean=0, head=0,
           ra=(0, 0), la=(0, 0), rl=(0, 0), ll=(0, 0), hat=None,
           cap_col=None, robe=False, sword=None, staff=None, spear=None):
    """Articulated silhouette figure standing at (x, y) = ground under feet.

    ra/la = (upper, forearm) angles, rl/ll = (thigh, knee-bend) angles.
    sword=(angle, length) draws a blade from the right hand.
    Returns (head_center, shoulder); sets person.rh / .lh / .tip / .head.
    """
    f = 1 if facing >= 0 else -1

    def dirv(a):
        r = math.radians(a)
        return (f * math.sin(r), math.cos(r))

    def add(p, v, L):
        return (p[0] + v[0] * L, p[1] + v[1] * L)

    ops = []

    # ---- legs (drawn first so robes overlap them) -------------------
    hip = (x, y - 56 * s)
    feet = []
    for a, bend in (rl, ll):
        knee = add(hip, dirv(a), 30 * s)
        foot = add(knee, dirv(a - bend), 27 * s)
        feet.append(foot)
        ops.append(_L(hip, knee, 11.5 * s, col))
        ops.append(_L(knee, foot, 8.5 * s, col))
        ops.append(_C(foot[0] + f * 3 * s, foot[1] + 1.5 * s, 5.2 * s, col))

    # ---- torso ------------------------------------------------------
    up = dirv(180 - lean)
    shoulder = add(hip, up, 34 * s)
    ops.append(_L(hip, shoulder, 18 * s, col))
    ops.append(_C(hip[0], hip[1], 9 * s, col))

    if robe:
        # flowing outer garment from shoulders to ground
        sk = [
            (shoulder[0] - f * 9 * s, shoulder[1] + 2 * s),
            (shoulder[0] + f * 11 * s, shoulder[1] + 5 * s),
            (x + f * 16 * s, y - 10 * s),
            (x + f * 13 * s, y + 1 * s),
            (x - f * 15 * s, y + 1 * s),
            (x - f * 13 * s, y - 12 * s),
            (hip[0] - f * 11 * s, hip[1] + 6 * s),
        ]
        ops.append(_P(sk, col))

    # ---- head -------------------------------------------------------
    neck = add(shoulder, up, 8 * s)
    head_c = (neck[0] + f * head * s, neck[1] - 10 * s)
    ops.append(_C(head_c[0], head_c[1], 9.5 * s, col))
    hcol = cap_col if cap_col is not None else col
    if hat == "turban":
        ops.append(_E(head_c[0] - f * 1.5 * s, head_c[1] - 5 * s, 11.5 * s, 8 * s, hcol))
        ops.append(_C(head_c[0] - f * 10 * s, head_c[1] - 8 * s, 3.2 * s, hcol))
    elif hat == "helm":
        ops.append(_E(head_c[0] - f * 1.5 * s, head_c[1] - 5 * s, 10 * s, 8.5 * s, hcol))
        ops.append(_P([(head_c[0] - f * 3 * s, head_c[1] - 13 * s),
                       (head_c[0] + f * 2 * s, head_c[1] - 17 * s),
                       (head_c[0] + f * 3 * s, head_c[1] - 11 * s)], hcol))
    elif hat == "cap":
        ops.append(_E(head_c[0] - f * 1 * s, head_c[1] - 6 * s, 9.5 * s, 7 * s, hcol))

    # ---- arms -------------------------------------------------------
    hands = {}
    for key, angles, back in (("rh", ra, 0.0), ("lh", la, -2.2 * s)):
        sh_a = (shoulder[0] - f * back, shoulder[1] + abs(back) * 0.6)
        elbow = add(sh_a, dirv(angles[0]), 22 * s)
        hand = add(elbow, dirv(angles[1]), 20 * s)
        ops.append(_L(sh_a, elbow, 8.2 * s, col))
        ops.append(_L(elbow, hand, 6.5 * s, col))
        ops.append(_C(hand[0], hand[1], 4.3 * s, col))
        hands[key] = hand

    # ---- weapons ----------------------------------------------------
    tip = hands["rh"]
    if sword is not None:
        ang, length = sword
        tip = add(hands["rh"], dirv(ang), length * s)
        g = dirv(ang + 90)
        ops.append(_L(hands["rh"], tip, 3.4 * s, col))
        ops.append(_L((hands["rh"][0] + g[0] * 4.5 * s, hands["rh"][1] + g[1] * 4.5 * s),
                      (hands["rh"][0] - g[0] * 4.5 * s, hands["rh"][1] - g[1] * 4.5 * s),
                      2.6 * s, col))
    if staff is not None:
        ang, length = staff
        a0 = add(hands["rh"], dirv(ang), -8 * s)
        tip = add(hands["rh"], dirv(ang), length * s)
        ops.append(_L(a0, tip, 2.8 * s, col))
    if spear is not None:
        ang, length = spear
        a0 = add(hands["lh"], dirv(ang), -length * 0.35 * s)
        tip = add(hands["lh"], dirv(ang), length * s)
        ops.append(_L(a0, tip, 2.6 * s, col))
        ops.append(_P([add(tip, dirv(ang), 9 * s),
                       add(tip, dirv(ang + 90), 3.4 * s),
                       add(tip, dirv(ang - 90), 3.4 * s)], col))

    paint_rimmed(c, ops, s, f, rim)
    person.rh, person.lh, person.head, person.tip = hands["rh"], hands["lh"], head_c, tip
    return head_c, shoulder


# ------------------------------------------------------------------ cape
def cape(c, sh, s, f, p, col, length=60, spread=26, amp=7, edge=None):
    pts_top, pts_bot = [], []
    for i in range(0, 7):
        u = i / 6
        x = sh[0] - f * (u * length) * s
        wave = math.sin(p * 1.0 - u * 4.0) * amp * u * s
        pts_top.append((x, sh[1] + 2 * s * u + wave))
        pts_bot.append((x - f * 2 * s * u,
                        sh[1] + (spread * u * 0.9 + 8 * (1 - u)) * s + wave * 1.3))
    c.poly(pts_top + pts_bot[::-1], col)
    if edge:
        c.path(pts_bot, 1.8 * s, edge)


# ------------------------------------------------------------------ seated rider
def seated(c, saddle, s, f, col, lean=14, rim=None, **kw):
    """Seat a person on a saddle point; returns (head, shoulder)."""
    sp = s
    ground = saddle[1] + 42 * sp
    return person(c, saddle[0], ground, sp, facing=f, col=col, rim=rim, lean=lean,
                  rl=(62, 34), ll=(58, 38), **kw)


# ------------------------------------------------------------------ horse
def horse(c, x, y, s=1.0, p=0.0, col="0a0508", rim=None, facing=1, mane=None,
          rider=None, speed_lean=0, bob=True):
    """Galloping silhouette horse; (x, y) = ground under the barrel.

    rider: optional callback rider(canvas, saddle_xy, s, phase, facing, ground_y).
    """
    f = 1 if facing >= 0 else -1
    mcol = mane if mane is not None else col
    bob_y = -3.0 * s * math.sin(p * 2) if bob else 0.0
    ops = []

    def B(px, py):
        """body-local point with gallop bob"""
        return (x + f * px * s, y + (py * s) + bob_y)

    # barrel + chest + rump
    ops.append(_P([B(-38, -74), B(20, -78), B(36, -66), B(34, -46),
                   B(10, -40), B(-30, -42), B(-42, -56)], col))
    # neck
    ops.append(_P([B(18, -74), B(30, -104), B(44, -112), B(52, -104),
                   B(38, -70), B(26, -62)], col))
    # head + muzzle
    ops.append(_P([B(30, -110), B(52, -116), B(66, -108), B(68, -99),
                   B(56, -94), B(40, -96), B(30, -100)], col))
    # ears
    ops.append(_P([B(33, -113), B(35, -124), B(41, -115)], col))
    ops.append(_P([B(41, -115), B(45, -125), B(49, -115)], col))
    # mane along the neck
    ops.append(_P([B(28, -108), B(22, -80), B(16, -70), B(20, -72),
                   B(26, -96), B(30, -112)], mcol))
    # tail
    tl = 0.5 + 0.5 * math.sin(p - 1.2)
    ops.append(_P([B(-40, -72), B(-58, -66 + 6 * tl), B(-72, -50 + 12 * tl),
                   B(-78, -30 + 14 * tl), B(-70, -34 + 12 * tl),
                   B(-56, -50 + 8 * tl), B(-38, -58)], col))
    # legs: [front-far, front-near, hind-far, hind-near]
    legs = ((26, -52, p + 3.4), (22, -52, p + 0.2),
            (-24, -50, p + 1.9), (-28, -50, p + 4.9))
    for lx, ly, ph in legs:
        hipx, hipy = lx, ly
        a = 32 * math.sin(ph)
        bend = 42 * max(0.0, math.sin(ph - 1.1)) + 10
        kx = hipx + math.sin(math.radians(a)) * 20
        ky = hipy + math.cos(math.radians(a)) * 20
        a2 = a - bend
        fx = kx + math.sin(math.radians(a2)) * 22
        fy = ky + math.cos(math.radians(a2)) * 22
        ops.append(_L(B(hipx, hipy), B(kx, ky), 9.5 * s, col))
        ops.append(_L(B(kx, ky), B(fx, fy), 7 * s, col))
        ops.append(_C(x + f * fx * s + f * 2 * s, y + fy * s + bob_y + 2 * s, 4.4 * s, col))
    # saddle pad
    ops.append(_P([B(-14, -80), B(14, -80), B(16, -70), B(-16, -70)], col))

    paint_rimmed(c, ops, s, f, rim)

    if rider is not None:
        sad = (x + f * 2 * s, y - 80 * s + bob_y)
        rider(c, sad, s, p, f, y)


# ------------------------------------------------------------------ camel
def camel(c, x, y, s=1.0, p=0.0, col="0a0508", rim=None, facing=1):
    f = 1 if facing >= 0 else -1
    bob_y = -2.0 * s * math.sin(p * 2)
    ops = []

    def B(px, py):
        return (x + f * px * s, y + (py * s) + bob_y)

    # barrel + hump + chest
    ops.append(_P([B(-36, -62), B(-20, -84), B(-6, -88), B(8, -80),
                   B(24, -68), B(30, -50), B(22, -38), B(-24, -38), B(-38, -48)], col))
    # neck + head
    ops.append(_P([B(22, -66), B(30, -100), B(38, -118), B(50, -122),
                   B(54, -114), B(44, -108), B(36, -88), B(30, -62)], col))
    ops.append(_P([B(38, -120), B(54, -126), B(62, -120), B(58, -113),
                   B(44, -112), B(36, -114)], col))
    # tail
    ops.append(_P([B(-36, -58), B(-48, -50 + 4 * math.sin(p)), B(-50, -38 + 5 * math.sin(p)),
                   B(-44, -40), B(-34, -50)], col))
    # legs
    legs = ((20, -40, p + 3.2), (16, -40, p + 0.1),
            (-20, -40, p + 1.7), (-24, -40, p + 4.8))
    for lx, ly, ph in legs:
        a = 22 * math.sin(ph)
        bend = 26 * max(0.0, math.sin(ph - 1.0)) + 6
        kx = lx + math.sin(math.radians(a)) * 22
        ky = ly + math.cos(math.radians(a)) * 22
        a2 = a - bend
        fx = kx + math.sin(math.radians(a2)) * 24
        fy = ky + math.cos(math.radians(a2)) * 24
        ops.append(_L(B(lx, ly), B(kx, ky), 8.5 * s, col))
        ops.append(_L(B(kx, ky), B(fx, fy), 6.2 * s, col))
        ops.append(_C(x + f * fx * s + f * 2 * s, y + fy * s + bob_y + 2 * s, 4 * s, col))

    paint_rimmed(c, ops, s, f, rim)


# ------------------------------------------------------------------ sky
def stars(c, n, seed, t, ymax):
    rnd = random.Random(seed)
    for i in range(n):
        x = rnd.random() * c.W
        yy = rnd.random() * ymax
        tw = 0.5 + 0.5 * math.sin(TAU * (t * (0.4 + 0.9 * rnd.random()) + rnd.random()))
        r = 0.5 + 1.5 * tw
        c.circle(x, yy, r, mix((170, 190, 255), (255, 255, 245), tw))
