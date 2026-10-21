#!/usr/bin/env python3
"""Render every animated slide scene to an animated GIF.

    python3 make_gifs.py            # write all GIFs into ../assets/anim/
    python3 make_gifs.py --sheet    # also write contact sheets to /tmp for review

Each scene is a seamless loop: frame k renders t = k / N, GIF duration is chosen
so the loop plays at roughly real-time speed in PowerPoint.
"""

import os
import sys
import time

from PIL import Image

from lib import Canvas  # noqa: F401  (re-exported for scene modules)
import scenes1
import scenes2
import scenes3

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "anim")
OUT = os.path.normpath(OUT)

# name -> (fn, W, H, frames, frame_ms)
SCENES = {
    "intro":     (scenes2.intro,     400, 500, 32, 65),
    "market":    (scenes2.market,    400, 500, 32, 65),
    "ghori":     (scenes2.damyak,    400, 500, 32, 65),
    "aibak":     (scenes2.polo,      400, 500, 32, 65),
    "iltutmish": (scenes2.iltutmish, 400, 500, 32, 65),
    "mongol":    (scenes1.mongol,    400, 500, 32, 65),
    "razia":     (scenes1.razia,     400, 500, 32, 65),
    "puppet":    (scenes3.puppet,    400, 500, 32, 65),
    "balban":    (scenes3.balban,    400, 500, 32, 65),
    "duel":      (scenes1.duel,      400, 500, 32, 65),
    "tanka":     (scenes3.tanka,     400, 400, 28, 70),
    "minar":     (scenes3.minar,     400, 590, 32, 70),
    "legacy":    (scenes3.legacy,    400, 545, 32, 70),
}


def to_palette(im, colors=96):
    return im.convert("P", palette=Image.ADAPTIVE, colors=colors)


def build(name, fn, W, H, frames, ms, sheet_dir=None):
    t0 = time.time()
    ims = []
    for k in range(frames):
        ims.append(fn(k / frames, W, H))
    pal = [to_palette(im) for im in ims]
    path = os.path.join(OUT, f"{name}.gif")
    pal[0].save(path, save_all=True, append_images=pal[1:], duration=ms,
                loop=0, optimize=True, disposal=2)
    kb = os.path.getsize(path) / 1024
    print(f"  {name:10s} {W}x{H} x{frames} -> {os.path.basename(path)}  "
          f"{kb:6.0f} KB  ({time.time() - t0:.1f}s)")
    if sheet_dir:
        cols = 6
        rows = (frames + cols - 1) // cols
        th_w, th_h = W // 3, H // 3
        sheet = Image.new("RGB", (cols * th_w, rows * th_h), "white")
        for k, im in enumerate(ims):
            th = im.resize((th_w, th_h), Image.LANCZOS)
            sheet.paste(th, ((k % cols) * th_w, (k // cols) * th_h))
        sheet.save(os.path.join(sheet_dir, f"sheet_{name}.png"))
    return path


def main():
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    want_sheet = "--sheet" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    sheet_dir = "/tmp/anim_sheets" if want_sheet else None
    if sheet_dir:
        os.makedirs(sheet_dir, exist_ok=True)
    names = only or list(SCENES)
    for name in names:
        fn, W, H, frames, ms = SCENES[name]
        build(name, fn, W, H, frames, ms, sheet_dir)


if __name__ == "__main__":
    main()
