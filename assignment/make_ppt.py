#!/usr/bin/env python3
"""Slave Dynasty (Mamluk) presentation v2 — interactive:
 - pictures on almost every slide (framed, captioned)
 - entrance animations (heading wipes in, image zooms in automatically,
   bullets fade in one-by-one on click)
 - fade transition between slides
Theme matched to the assignment PDF (cream / brown / Bernard MT Condensed)."""

import itertools
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.enum.shapes import MSO_SHAPE
from pptx.oxml import parse_xml
from PIL import Image

ASSETS = "/home/user/SIH/assignment/assets"

CREAM = RGBColor(0xFD, 0xF9, 0xF2)
BROWN = RGBColor(0x80, 0x34, 0x0D)
BROWN2 = RGBColor(0xA8, 0x55, 0x1E)
DARK = RGBColor(0x26, 0x1A, 0x10)
GREEN = RGBColor(0x0C, 0x35, 0x12)
GRAY = RGBColor(0x7F, 0x7F, 0x7F)
GOLD = RGBColor(0xC8, 0x8A, 0x3C)

HEAD_FONT = "Bernard MT Condensed"
BODY_FONT = "Times New Roman"

NS = ('xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"')

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
SW, SH = prs.slide_width, prs.slide_height
blank = prs.slide_layouts[6]


# ====================================================================
#  ANIMATION ENGINE  (raw PML timing XML)
# ====================================================================
class Animator:
    """Collects effects for one slide, then writes <p:transition> + <p:timing>."""

    def __init__(self, slide):
        self.slide = slide
        self.groups = []          # list of (click: bool, [effect dicts])
        self.builds = []          # (spid, by_paragraph)
        self._id = itertools.count(3)

    # kind: fade | wipe | zoom ; prg: paragraph index or None
    def add_group(self, effects, click=True):
        self.groups.append((click, effects))

    def build_para(self, spid):
        if (spid, True) not in self.builds:
            self.builds.append((spid, True))

    def build_shape(self, spid):
        if (spid, False) not in self.builds:
            self.builds.append((spid, False))

    # ---------------------------------------------------------------
    def _tgt(self, spid, prg):
        if prg is None:
            return f'<p:tgtEl><p:spTgt spid="{spid}"/></p:tgtEl>'
        return (f'<p:tgtEl><p:spTgt spid="{spid}"><p:txEl>'
                f'<p:pRg st="{prg}" end="{prg}"/></p:txEl></p:spTgt></p:tgtEl>')

    def _effect(self, e, ntype):
        spid, kind, prg = e["spid"], e["kind"], e.get("prg")
        delay = e.get("delay", 0)
        dur = e.get("dur", 500)
        rep = e.get("repeat")            # None | "indefinite" | int (times)
        tgt = self._tgt(spid, prg)
        i1 = next(self._id)
        rep_attr = ""
        if rep is not None:
            rep_attr = (' repeatCount="indefinite"' if rep == "indefinite"
                        else f' repeatCount="{int(rep) * 1000}"')

        def _set_visible():
            i = next(self._id)
            return (
                f'<p:set><p:cBhvr><p:cTn id="{i}" dur="1" fill="hold">'
                f'<p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn>{tgt}'
                f'<p:attrNameLst><p:attrName>style.visibility</p:attrName>'
                f'</p:attrNameLst></p:cBhvr><p:to><p:strVal val="visible"/></p:to></p:set>'
            )

        # ---------- motion along a path (shape already visible) ----------
        if kind == "motion":
            i2 = next(self._id)
            inner = (
                f'<p:animMotion origin="layout" path="{e["path"]}" '
                f'pathEditMode="relative" ptsTypes="">'
                f'<p:cBhvr><p:cTn id="{i2}" dur="{dur}"{rep_attr} fill="hold"/>{tgt}'
                f'<p:attrNameLst><p:attrName>ppt_x</p:attrName>'
                f'<p:attrName>ppt_y</p:attrName></p:attrNameLst>'
                f'</p:cBhvr></p:animMotion>'
            )
            preset, pclass = 0, "path"
        # ---------- fly-in entrance along a path (+ optional swing) ------
        elif kind == "fly":
            inner = _set_visible()
            i2 = next(self._id)
            inner += (
                f'<p:animMotion origin="layout" path="{e["path"]}" '
                f'pathEditMode="relative" ptsTypes="">'
                f'<p:cBhvr><p:cTn id="{i2}" dur="{dur}" fill="hold"/>{tgt}'
                f'<p:attrNameLst><p:attrName>ppt_x</p:attrName>'
                f'<p:attrName>ppt_y</p:attrName></p:attrNameLst>'
                f'</p:cBhvr></p:animMotion>'
            )
            if e.get("swing"):
                i3 = next(self._id)
                inner += (
                    f'<p:animRot by="{int(e["swing"] * 60000)}">'
                    f'<p:cBhvr><p:cTn id="{i3}" dur="{dur}" fill="hold"/>{tgt}'
                    f'<p:attrNameLst><p:attrName>r</p:attrName></p:attrNameLst>'
                    f'</p:cBhvr></p:animRot>'
                )
            preset, pclass = 2, "entr"
        # ---------- Ken Burns: slow cinematic zoom + pan (like videos) ----
        elif kind == "kenburns":
            i2, i3 = next(self._id), next(self._id)
            path = e.get("path", "M 0 0 L -0.016 -0.009 E")
            zoom_to = e.get("zoom_to", 113000)
            inner = (
                f'<p:animScale><p:cBhvr><p:cTn id="{i2}" dur="{dur}" fill="hold"/>'
                f'{tgt}</p:cBhvr><p:from x="100000" y="100000"/>'
                f'<p:to x="{zoom_to}" y="{zoom_to}"/></p:animScale>'
                f'<p:animMotion origin="layout" path="{path}" '
                f'pathEditMode="relative" ptsTypes="">'
                f'<p:cBhvr><p:cTn id="{i3}" dur="{dur}" fill="hold"/>{tgt}'
                f'<p:attrNameLst><p:attrName>ppt_x</p:attrName>'
                f'<p:attrName>ppt_y</p:attrName></p:attrNameLst>'
                f'</p:cBhvr></p:animMotion>'
            )
            preset, pclass = 6, "emph"
        # ---------- continuous spin (emphasis) ---------------------------
        elif kind == "spin":
            i2 = next(self._id)
            inner = (
                f'<p:animRot by="{int(e.get("deg", 360) * 60000)}">'
                f'<p:cBhvr><p:cTn id="{i2}" dur="{dur}"{rep_attr} fill="hold"/>{tgt}'
                f'<p:attrNameLst><p:attrName>r</p:attrName></p:attrNameLst>'
                f'</p:cBhvr></p:animRot>'
            )
            preset, pclass = 8, "emph"
        # ---------- pulse (emphasis) --------------------------------------
        elif kind == "pulse":
            i2 = next(self._id)
            inner = (
                f'<p:animScale><p:cBhvr>'
                f'<p:cTn id="{i2}" dur="{dur}" autoRev="1"{rep_attr} fill="hold"/>{tgt}'
                f'</p:cBhvr><p:by x="110000" y="110000"/></p:animScale>'
            )
            preset, pclass = 26, "emph"
        # ---------- entrances: fade / wipe / wipeup / zoom ----------------
        else:
            preset = {"fade": 10, "wipe": 22, "wipeup": 22, "zoom": 53}[kind]
            pclass = "entr"
            inner = _set_visible()
            i3 = next(self._id)
            filt = {"wipe": "wipe(down)", "wipeup": "wipe(up)"}.get(kind, "fade")
            inner += (f'<p:animEffect transition="in" filter="{filt}">'
                      f'<p:cBhvr><p:cTn id="{i3}" dur="{dur}"/>{tgt}</p:cBhvr></p:animEffect>')
            if kind == "zoom":
                i4 = next(self._id)
                inner += (
                    f'<p:animScale><p:cBhvr><p:cTn id="{i4}" dur="{dur}" fill="hold"/>'
                    f'{tgt}</p:cBhvr><p:from x="20000" y="20000"/>'
                    f'<p:to x="100000" y="100000"/></p:animScale>'
                )
        return (
            f'<p:par><p:cTn id="{i1}" presetID="{preset}" presetClass="{pclass}" '
            f'presetSubtype="0" fill="hold" grpId="0" nodeType="{ntype}">'
            f'<p:stCondLst><p:cond delay="{delay}"/></p:stCondLst>'
            f'<p:childTnLst>{inner}</p:childTnLst></p:cTn></p:par>'
        )

    def _group(self, click, effects):
        d = "indefinite" if click else "0"
        g1, g2 = next(self._id), next(self._id)
        inner = ""
        for k, e in enumerate(effects):
            if click:
                ntype = "clickEffect" if k == 0 else "withEffect"
            else:
                ntype = "afterEffect" if k == 0 else "withEffect"
            inner += self._effect(e, ntype)
        return (
            f'<p:par><p:cTn id="{g1}" fill="hold">'
            f'<p:stCondLst><p:cond delay="{d}"/></p:stCondLst><p:childTnLst>'
            f'<p:par><p:cTn id="{g2}" fill="hold">'
            f'<p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>'
            f'{inner}'
            f'</p:childTnLst></p:cTn></p:par>'
            f'</p:childTnLst></p:cTn></p:par>'
        )

    def apply(self):
        sld = self.slide._element
        # slide transition (fade)
        sld.append(parse_xml(f'<p:transition {NS} spd="med"><p:fade/></p:transition>'))
        if not self.groups:
            return
        groups_xml = "".join(self._group(c, e) for c, e in self.groups)
        builds = ""
        for spid, by_p in self.builds:
            builds += (f'<p:bldP spid="{spid}" grpId="0" build="p"/>' if by_p
                       else f'<p:bldP spid="{spid}" grpId="0"/>')
        timing = (
            f'<p:timing {NS}><p:tnLst><p:par>'
            f'<p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot">'
            f'<p:childTnLst><p:seq concurrent="1" nextAc="seek">'
            f'<p:cTn id="2" dur="indefinite" nodeType="mainSeq"><p:childTnLst>'
            f'{groups_xml}'
            f'</p:childTnLst></p:cTn>'
            f'<p:prevCondLst><p:cond evt="onPrev" delay="0"><p:tgtEl><p:sldTgt/>'
            f'</p:tgtEl></p:cond></p:prevCondLst>'
            f'<p:nextCondLst><p:cond evt="onNext" delay="0"><p:tgtEl><p:sldTgt/>'
            f'</p:tgtEl></p:cond></p:nextCondLst>'
            f'</p:seq></p:childTnLst></p:cTn></p:par></p:tnLst>'
            f'<p:bldLst>{builds}</p:bldLst></p:timing>'
        )
        sld.append(parse_xml(timing))


# ====================================================================
#  LAYOUT HELPERS
# ====================================================================
def add_slide():
    s = prs.slides.add_slide(blank)
    s.background.fill.solid()
    s.background.fill.fore_color.rgb = CREAM
    return s, Animator(s)


def box(slide, l, t, w, h):
    tb = slide.shapes.add_textbox(l, t, w, h)
    tb.text_frame.word_wrap = True
    return tb


def set_run(r, text, size, font=BODY_FONT, color=DARK, bold=False, italic=False):
    r.text = text
    r.font.name = font
    r.font.size = Pt(size)
    r.font.color.rgb = color
    r.font.bold = bold
    r.font.italic = italic


def side_bar(slide):
    for x, w, c in ((0, 0.22, BROWN), (0.22, 0.07, GOLD)):
        bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), 0, Inches(w), SH)
        bar.fill.solid(); bar.fill.fore_color.rgb = c
        bar.line.fill.background(); bar.shadow.inherit = False


def footer(slide, n):
    tb = box(slide, SW - Inches(1.6), SH - Inches(0.45), Inches(1.3), Inches(0.3))
    p = tb.text_frame.paragraphs[0]
    p.alignment = PP_ALIGN.RIGHT
    set_run(p.add_run(), f"{n} | Page", 11, BODY_FONT, GRAY)


def heading(slide, anim, text, size=36):
    tb = box(slide, Inches(0.65), Inches(0.32), SW - Inches(1.3), Inches(0.95))
    p = tb.text_frame.paragraphs[0]
    r = p.add_run()
    set_run(r, text, size, HEAD_FONT, BROWN)
    r.font.underline = True
    anim.add_group([{"spid": tb.shape_id, "kind": "wipe", "dur": 600}], click=False)
    anim.build_shape(tb.shape_id)
    return tb


def bullets(slide, anim, items, l, t, w, h, size=17, gap=12, per_click=True):
    tb = box(slide, l, t, w, h)
    tf = tb.text_frame
    first = True
    for item in items:
        p = tf.paragraphs[0] if first else tf.add_paragraph()
        first = False
        p.space_after = Pt(gap)
        rb = p.add_run()
        set_run(rb, "\u27a2  ", size, "Arial", BROWN, bold=True)
        if isinstance(item, tuple):
            r1 = p.add_run(); set_run(r1, item[0], size, BODY_FONT, DARK, bold=True)
            r2 = p.add_run(); set_run(r2, item[1], size, BODY_FONT, DARK)
        else:
            r = p.add_run(); set_run(r, item, size, BODY_FONT, DARK)
    # one click per paragraph
    for k in range(len(items)):
        anim.add_group([{"spid": tb.shape_id, "kind": "fade", "prg": k, "dur": 400}],
                       click=per_click)
    anim.build_para(tb.shape_id)
    return tb


_PAN_CYCLE = itertools.cycle([
    "M 0 0 L -0.018 -0.01 E", "M 0 0 L 0.016 -0.009 E",
    "M 0 0 L -0.014 0.01 E", "M 0 0 L 0.018 0.008 E",
])


def picture(slide, anim, path, l, t, w, h, caption=None, effect="zoom",
            effect_dur=600, ken=False):
    """Aspect-fit crop into box, brown frame, optional caption. Returns pic."""
    iw, ih = Image.open(path).size
    box_ratio = w / h
    img_ratio = iw / ih
    if img_ratio > box_ratio:
        nh, nw = h, int(h * img_ratio)
    else:
        nw, nh = w, int(w / img_ratio)
    pic = slide.shapes.add_picture(path, l, t, nw, nh)
    cl = max(0, (nw - w) / 2 / nw)
    ct = max(0, (nh - h) / 2 / nh)
    pic.crop_left = cl; pic.crop_right = cl
    pic.crop_top = ct; pic.crop_bottom = ct
    pic.left, pic.top, pic.width, pic.height = l, t, w, h
    pic.line.color.rgb = BROWN
    pic.line.width = Pt(2)
    shapes = [pic]
    if caption:
        cap = box(slide, l - Inches(0.3), t + h + Inches(0.06), w + Inches(0.6), Inches(0.55))
        p = cap.text_frame.paragraphs[0]
        p.alignment = PP_ALIGN.CENTER
        set_run(p.add_run(), caption, 12, BODY_FONT, GRAY, italic=True)
        shapes.append(cap)
    effs = []
    for i, sp in enumerate(shapes):
        k = effect if i == 0 else "fade"
        effs.append({"spid": sp.shape_id, "kind": k, "dur": effect_dur, "delay": 150 * i})
    anim.add_group(effs, click=False)
    if ken:
        # cinematic slow zoom + drift, exactly like documentary videos
        anim.add_group([{"spid": pic.shape_id, "kind": "kenburns",
                         "dur": 10000, "path": next(_PAN_CYCLE)}], click=False)
    for sp in shapes:
        anim.build_shape(sp.shape_id)
    return pic


def prop(slide, path, l, t, w, h):
    """Transparent PNG prop (horse / sword / arrow) — no frame, no auto-anim."""
    pic = slide.shapes.add_picture(path, l, t, w, h)
    return pic


GALLOP = ("M 0 0 L 0.1 -0.015 L 0.2 0 L 0.3 -0.015 L 0.4 0 L 0.5 -0.015 "
          "L 0.6 0 L 0.7 -0.015 L 0.8 0 L 0.9 -0.015 L 1.0 0 L 1.18 0 E")

WHITE = RGBColor(0xFF, 0xFF, 0xFF)
CREAM2 = RGBColor(0xFF, 0xE9, 0xC9)
BLUE = RGBColor(0x3B, 0x6E, 0xA5)
GREEN2 = RGBColor(0x2E, 0x6B, 0x33)


def dbox(slide, lines, l, t, w, h, fill=BROWN, line_c=GOLD,
         shape=MSO_SHAPE.ROUNDED_RECTANGLE):
    """Diagram box. lines = [(text, size, color, font, bold), ...]"""
    sh = slide.shapes.add_shape(shape, Inches(l), Inches(t), Inches(w), Inches(h))
    if fill is None:
        sh.fill.background()
    else:
        sh.fill.solid(); sh.fill.fore_color.rgb = fill
    if line_c is None:
        sh.line.fill.background()
    else:
        sh.line.color.rgb = line_c; sh.line.width = Pt(1.5)
    sh.shadow.inherit = False
    tf = sh.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = Pt(3)
    tf.margin_top = tf.margin_bottom = Pt(2)
    for i, (txt, size, color, font, bold) in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.CENTER
        set_run(p.add_run(), txt, size, font, color, bold=bold)
    return sh


def dlabel(slide, text, l, t, w, size=12, color=GRAY, italic=True, bold=False,
           align=PP_ALIGN.CENTER):
    tb = box(slide, Inches(l), Inches(t), Inches(w), Inches(0.5))
    p = tb.text_frame.paragraphs[0]; p.alignment = align
    set_run(p.add_run(), text, size, BODY_FONT, color, bold=bold, italic=italic)
    return tb


def running_horse(slide, anim, t, w=1.5, dur=7000):
    """Horse+rider silhouette galloping across the slide, looping forever."""
    wi = Inches(w); hi = Emu(int(wi * 932 / 1205))
    horse = prop(slide, f"{ASSETS}/horse.png", -Emu(int(wi * 1.2)), t, wi, hi)
    anim.add_group([{"spid": horse.shape_id, "kind": "motion", "path": GALLOP,
                     "dur": dur, "repeat": "indefinite"}], click=False)
    return horse


# content slide with picture on the right
def content_slide(n, title, items, img=None, caption=None, size=17, gap=12,
                  img_w=3.3, img_h=4.3, extras=None, reserve_right=0.0,
                  img_effect="fade", ken=True):
    s, anim = add_slide()
    side_bar(s); footer(s, n)
    heading(s, anim, title)
    pic = None
    if img:
        iw, ih = Inches(img_w), Inches(img_h)
        il = SW - iw - Inches(0.55)
        it = Inches(1.55)
        pic = picture(s, anim, f"{ASSETS}/{img}", il, it, iw, ih, caption,
                      effect=img_effect, effect_dur=800, ken=ken)
        tw = il - Inches(1.05)
    elif reserve_right:
        tw = SW - Inches(1.7) - Inches(reserve_right)
    else:
        tw = SW - Inches(1.7)
    bullets(s, anim, items, Inches(0.8), Inches(1.5), tw, Inches(5.6), size=size, gap=gap)
    if extras:
        extras(s, anim, pic)
    anim.apply()
    return s


# ====================================================================
#  SLIDE 1 — TITLE (matches assignment cover)
# ====================================================================
s, anim = add_slide()
for y in (0, SH - Inches(0.18)):
    band = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, y, SW, Inches(0.18))
    band.fill.solid(); band.fill.fore_color.rgb = BROWN
    band.line.fill.background(); band.shadow.inherit = False

tb1 = box(s, Inches(0.5), Inches(0.4), SW - Inches(1.0), Inches(1.5))
p = tb1.text_frame.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
r = p.add_run(); set_run(r, "LOVELY PROFESSIONAL UNIVERSITY", 40, HEAD_FONT, DARK); r.font.underline = True
p2 = tb1.text_frame.add_paragraph(); p2.alignment = PP_ALIGN.CENTER; p2.space_before = Pt(6)
r = p2.add_run(); set_run(r, "SCHOOL OF LAW", 26, HEAD_FONT, DARK); r.font.underline = True

seal_w = Inches(1.7)
seal = s.shapes.add_picture(f"{ASSETS}/lpu_seal.jpg", int((SW - seal_w) / 2), Inches(1.95),
                            seal_w, int(seal_w * 133.45 / 132.0))

# side art on title slide (aspect-fit crop into 1.7 x 3.4 box)
def _art(path, l):
    iw, ih = Image.open(path).size
    bw_, bh_ = Inches(1.7), Inches(3.4)
    box_ratio = bw_ / bh_
    img_ratio = iw / ih
    pic = s.shapes.add_picture(path, l, Inches(2.1), bw_, bh_)
    if img_ratio > box_ratio:          # too wide -> crop sides
        keep = box_ratio / img_ratio
        c = (1 - keep) / 2
        pic.crop_left = c; pic.crop_right = c
    else:                              # too tall -> crop top/bottom
        keep = img_ratio / box_ratio
        c = (1 - keep) / 2
        pic.crop_top = c; pic.crop_bottom = c
    pic.left, pic.top, pic.width, pic.height = l, Inches(2.1), bw_, bh_
    pic.line.color.rgb = GOLD; pic.line.width = Pt(2)
    return pic

art_l = _art(f"{ASSETS}/qutb_minar.jpg", Inches(0.55))
art_r = _art(f"{ASSETS}/mamluk_cavalry.jpg", SW - Inches(2.25))

tb2 = box(s, Inches(2.4), Inches(3.85), SW - Inches(4.8), Inches(1.7))
p = tb2.text_frame.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
set_run(p.add_run(), "CA \u2013 01 HISTORY (SSC231)", 22, HEAD_FONT, BROWN)
p2 = tb2.text_frame.add_paragraph(); p2.alignment = PP_ALIGN.CENTER; p2.space_before = Pt(4)
r = p2.add_run(); set_run(r, "SLAVE DYNASTY (MAMLUK DYNASTY)", 34, HEAD_FONT, BROWN); r.font.underline = True
p3 = tb2.text_frame.add_paragraph(); p3.alignment = PP_ALIGN.CENTER; p3.space_before = Pt(4)
set_run(p3.add_run(), "Delhi Sultanate \u2022 1206 \u2013 1290 CE", 16, BODY_FONT, DARK, italic=True)

tb3 = box(s, Inches(2.75), Inches(5.6), Inches(4.4), Inches(1.6))
tf = tb3.text_frame
set_run(tf.paragraphs[0].add_run(), "Submitted by :", 19, HEAD_FONT, DARK)
for line in ["Sangam Sitapuri", "Reg. no. \u2013 RK202406B65", "Course \u2013 SSC231"]:
    pp = tf.add_paragraph(); pp.space_before = Pt(2)
    set_run(pp.add_run(), line, 14, BODY_FONT, DARK, bold=True)

tb4 = box(s, Inches(7.65), Inches(5.6), Inches(3.6), Inches(1.6))
tf = tb4.text_frame
set_run(tf.paragraphs[0].add_run(), "Submitted to :", 19, HEAD_FONT, DARK)
pp = tf.add_paragraph(); pp.space_before = Pt(2)
r = pp.add_run(); set_run(r, "Dr. Vandana Arya", 14, BODY_FONT, DARK, bold=True); r.font.underline = True

anim.add_group([{"spid": tb1.shape_id, "kind": "wipe", "dur": 700}], click=False)
anim.add_group([{"spid": seal.shape_id, "kind": "zoom", "dur": 700},
                {"spid": art_l.shape_id, "kind": "fade", "dur": 700, "delay": 200},
                {"spid": art_r.shape_id, "kind": "fade", "dur": 700, "delay": 350}], click=False)
anim.add_group([{"spid": tb2.shape_id, "kind": "zoom", "dur": 600}], click=False)
anim.add_group([{"spid": tb3.shape_id, "kind": "fade", "dur": 500},
                {"spid": tb4.shape_id, "kind": "fade", "dur": 500, "delay": 200}], click=False)
for t in (tb1, tb2, tb3, tb4):
    anim.build_shape(t.shape_id)
anim.build_shape(seal.shape_id); anim.build_shape(art_l.shape_id); anim.build_shape(art_r.shape_id)
# galloping horse rides across the bottom of the title slide, forever
running_horse(s, anim, Inches(6.1), w=1.55, dur=7000)
anim.apply()

# ====================================================================
#  SLIDE 2 — TABLE OF CONTENT
# ====================================================================
s, anim = add_slide()
side_bar(s); footer(s, 2)
tb = box(s, Inches(0.65), Inches(0.32), SW - Inches(1.3), Inches(0.95))
p = tb.text_frame.paragraphs[0]
r = p.add_run(); set_run(r, "TABLE OF CONTENT", 38, HEAD_FONT, GREEN); r.font.underline = True
anim.add_group([{"spid": tb.shape_id, "kind": "wipe", "dur": 600}], click=False)
anim.build_shape(tb.shape_id)

items_l = ["Introduction", "Timeline at a Glance", "Who Were the Mamluks?",
           "1206 \u2013 Birth of the Sultanate", "Qutb-ud-din Aibak",
           "Iltutmish \u2013 The Real Founder", "The Mongol Storm (1221)", "Razia Sultan"]
items_r = ["The Puppet Years (1240\u201366)", "Balban \u2013 Blood and Iron",
           "Fall of the Dynasty (1290)", "Administration", "Art and Architecture",
           "Legacy and Significance", "Conclusion"]
cols = []
for items, lx, start in ((items_l, Inches(0.95), 1), (items_r, Inches(7.0), 9)):
    tbc = box(s, lx, Inches(1.55), Inches(5.7), Inches(5.5))
    tf = tbc.text_frame
    first = True
    for i, it in enumerate(items):
        p = tf.paragraphs[0] if first else tf.add_paragraph()
        first = False
        p.space_after = Pt(12)
        set_run(p.add_run(), f"{start + i:02d}.  ", 18, BODY_FONT, BROWN, bold=True)
        set_run(p.add_run(), it, 18, BODY_FONT, DARK, bold=True)
    cols.append(tbc)
anim.add_group([{"spid": cols[0].shape_id, "kind": "fade", "dur": 600},
                {"spid": cols[1].shape_id, "kind": "fade", "dur": 600, "delay": 300}], click=False)
for c in cols:
    anim.build_shape(c.shape_id)
anim.apply()

# ====================================================================
#  SLIDE 3 — INTRODUCTION  (animated: three houses, one throne)
# ====================================================================
def _three_houses(s, anim, pic):
    cards = [("HOUSE OF AIBAK", "1206 \u2013 1211", BROWN),
             ("HOUSE OF ILTUTMISH", "1211 \u2013 1266", BROWN2),
             ("HOUSE OF BALBAN", "1266 \u2013 1290", BROWN)]
    shapes = []
    y = 1.8
    for i, (name, yrs, fill) in enumerate(cards):
        c = dbox(s, [(name, 13, CREAM2, HEAD_FONT, False),
                     (yrs, 12, WHITE, BODY_FONT, True)], 9.5, y, 3.3, 1.0, fill=fill)
        shapes.append(("card", c))
        if i < 2:
            ar = dlabel(s, "\u25bc", 10.9, y + 1.02, 0.5, size=16, color=BROWN2,
                        italic=False, bold=True)
            shapes.append(("arrow", ar))
        y += 1.55
    capt = dlabel(s, "Three families \u2014 one throne", 9.5, y + 0.05, 3.3)
    effs, d = [], 0
    for kind, sp in shapes:
        effs.append({"spid": sp.shape_id,
                     "kind": "zoom" if kind == "card" else "fade",
                     "dur": 400, "delay": d})
        d += 380
    effs.append({"spid": capt.shape_id, "kind": "fade", "dur": 400, "delay": d})
    anim.add_group(effs, click=True)
    for _, sp in shapes:
        anim.build_shape(sp.shape_id)
    anim.build_shape(capt.shape_id)


content_slide(3, "INTRODUCTION", [
    ("Rulers of Delhi, 1206\u20131290 CE ", "\u2014 the first dynasty of the Delhi Sultanate, founded after Muhammad Ghori's death."),
    ("'Mamluk' ", "is Arabic for 'one who is owned'. Every sultan of this line was a former slave or a slave's descendant."),
    ("Nobody ruled as a slave ", "\u2014 each ruler was legally freed (manumitted) before taking the throne."),
    ("Really three families: ", "the houses of Aibak, Iltutmish and Balban, one after another."),
    ("Why it matters: ", "it laid the foundation of the Delhi Sultanate \u2014 Delhi as capital, the tanka coin, the iqta system, the Qutb Minar \u2014 shaping north India for 300 years."),
], img="anim/intro.gif", caption="From chains to crowns \u2014 the story begins",
    size=18, gap=14, img_w=3.5, img_h=4.4)

# ====================================================================
#  SLIDE 4 — TIMELINE AT A GLANCE (animated boxes)
# ====================================================================
s, anim = add_slide()
side_bar(s); footer(s, 4)
heading(s, anim, "TIMELINE AT A GLANCE")

line = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.9), Inches(4.0), SW - Inches(1.8), Inches(0.06))
line.fill.solid(); line.fill.fore_color.rgb = GOLD
line.line.fill.background(); line.shadow.inherit = False
anim.add_group([{"spid": line.shape_id, "kind": "wipe", "dur": 600}], click=False)
anim.build_shape(line.shape_id)

rulers = [
    ("1206\u201310", "Qutb-ud-din\nAibak", "Founder,\n'Lakh Baksh'"),
    ("1210\u201311", "Aram\nShah", "Weak interlude"),
    ("1211\u201336", "Iltutmish", "Real founder,\ntanka, Caliph"),
    ("1236\u201340", "Razia\nSultan", "Only woman\non the throne"),
    ("1240\u201366", "Puppet\nSultans", "Rule of\n'The Forty'"),
    ("1266\u201387", "Balban", "Blood & iron,\nZil-e-Ilahi"),
    ("1287\u201390", "Kaiqubad\n& fall", "Khalji\nRevolution"),
]
bw = Inches(1.58); gap_x = Inches(0.08)
total = len(rulers) * bw + (len(rulers) - 1) * gap_x
x0 = int((SW - total) / 2)
tl_shapes = []
for i, (yrs, name, note) in enumerate(rulers):
    x = x0 + i * (bw + gap_x)
    up = i % 2 == 0
    y = Inches(2.15) if up else Inches(4.3)
    card = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, x, y, bw, Inches(1.7))
    card.adjustments[0] = 0.12
    card.fill.solid(); card.fill.fore_color.rgb = BROWN if i % 2 == 0 else BROWN2
    card.line.color.rgb = GOLD; card.line.width = Pt(1.5)
    card.shadow.inherit = False
    tf = card.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
    set_run(p.add_run(), yrs, 15, HEAD_FONT, RGBColor(0xFF, 0xE9, 0xC9))
    for j, chunk in enumerate(name.split("\n")):
        pp = tf.add_paragraph(); pp.alignment = PP_ALIGN.CENTER
        set_run(pp.add_run(), chunk, 14, BODY_FONT, RGBColor(0xFF, 0xFF, 0xFF), bold=True)
    for chunk in note.split("\n"):
        pp = tf.add_paragraph(); pp.alignment = PP_ALIGN.CENTER
        set_run(pp.add_run(), chunk, 10.5, BODY_FONT, RGBColor(0xF5, 0xDE, 0xC0), italic=True)
    # connector dot
    dot = s.shapes.add_shape(MSO_SHAPE.OVAL, int(x + bw / 2 - Inches(0.08)),
                             Inches(3.95), Inches(0.16), Inches(0.16))
    dot.fill.solid(); dot.fill.fore_color.rgb = BROWN
    dot.line.color.rgb = GOLD; dot.line.width = Pt(1)
    dot.shadow.inherit = False
    tl_shapes.append((card, dot))

# first card on click, rest cascade automatically
effs = []
for i, (card, dot) in enumerate(tl_shapes):
    effs.append({"spid": dot.shape_id, "kind": "fade", "dur": 200, "delay": i * 350})
    effs.append({"spid": card.shape_id, "kind": "zoom", "dur": 350, "delay": i * 350 + 80})
anim.add_group(effs, click=True)
for card, dot in tl_shapes:
    anim.build_shape(card.shape_id); anim.build_shape(dot.shape_id)
# after the cards appear, a rider gallops down the timeline
running_horse(s, anim, Inches(3.18), w=1.15, dur=5500)
anim.apply()

# ====================================================================
#  CONTENT SLIDES
# ====================================================================
def _slave_ladder(s, anim, pic):
    """Slavery as a ladder — steps rise one by one, crown lands on top."""
    steps = ["Bought in the market", "Trained & converted", "Slave soldier",
             "General / Governor", "SULTAN"]
    shapes = []
    for i, txt in enumerate(steps):
        x = 9.15 + i * 0.22
        y = 6.15 - i * 0.93
        fill = BROWN if i < 4 else GREEN2
        st = dbox(s, [(txt, 12 if i < 4 else 14, WHITE if i < 4 else CREAM2,
                       BODY_FONT if i < 4 else HEAD_FONT, i < 4)],
                  x, y, 2.9, 0.78, fill=fill)
        shapes.append(st)
    crown = s.shapes.add_shape(MSO_SHAPE.STAR_5_POINT,
                               Inches(11.2), Inches(1.45), Inches(0.75), Inches(0.75))
    crown.fill.solid(); crown.fill.fore_color.rgb = GOLD
    crown.line.color.rgb = BROWN; crown.line.width = Pt(1.25)
    crown.shadow.inherit = False
    capt = dlabel(s, "Slavery was a ladder, not a pit", 9.3, 6.95, 3.6)
    effs = [{"spid": st.shape_id, "kind": "wipeup", "dur": 350, "delay": i * 380}
            for i, st in enumerate(shapes)]
    effs.append({"spid": crown.shape_id, "kind": "zoom", "dur": 350,
                 "delay": len(shapes) * 380})
    effs.append({"spid": capt.shape_id, "kind": "fade", "dur": 400,
                 "delay": len(shapes) * 380 + 300})
    anim.add_group(effs, click=True)
    anim.add_group([{"spid": crown.shape_id, "kind": "pulse", "dur": 700,
                     "repeat": 3}], click=False)
    for sp in shapes + [crown, capt]:
        anim.build_shape(sp.shape_id)


content_slide(5, "WHO WERE THE MAMLUKS?", [
    ("Elite military slaves ", "(bandagan) \u2014 Turkic boys bought in Central Asian markets, trained in war, horsemanship and court manners."),
    ("Loyalty by design: ", "cut off from family and clan, a slave soldier had nobody except his master."),
    ("Promotion purely on merit ", "\u2014 a talented slave could rise to general, governor\u2026 and eventually king."),
    ("Not plantation slavery: ", "they ate well, commanded armies, married into noble families \u2014 apprenticeship plus bonded loyalty."),
    ("Ghori's 'sons': ", "asked about having no heir, Ghori said his thousands of Turkish slaves would carry his name \u2014 and they did."),
], img="anim/market.gif", caption="A boy is bought in Bukhara\u2026 a sultan is made",
    size=17, gap=13, img_w=3.5, img_h=4.4)

def _empire_splits(s, anim, pic):
    """Ghori's empire shatters into three — boxes fly apart."""
    top = dbox(s, [("GHORI'S EMPIRE", 14, CREAM2, HEAD_FONT, False),
                   ("\u2020 murdered 1206", 11, WHITE, BODY_FONT, True)],
               9.75, 1.7, 2.9, 1.0, fill=DARK)
    rivals = [("YILDIZ", "Ghazni", BROWN2), ("QABACHA", "Multan\u2013Uch", BROWN2),
              ("AIBAK", "DELHI \u2714", GREEN2)]
    rboxes = []
    for i, (nm, place, fill) in enumerate(rivals):
        rb = dbox(s, [(nm, 12.5, CREAM2, HEAD_FONT, False),
                      (place, 11, WHITE, BODY_FONT, True)],
                  9.32 + i * 1.3, 3.75 + (0.35 if i == 1 else 0), 1.22, 0.95, fill=fill)
        rboxes.append(rb)
    capt = dlabel(s, "One empire \u2014 three swords drawn", 9.35, 5.35, 3.6)
    anim.add_group([{"spid": top.shape_id, "kind": "zoom", "dur": 500}], click=False)
    paths = ["M 0 -0.18 L -0.02 0 E", "M 0 -0.22 L 0 0 E", "M 0 -0.26 L 0.02 0 E"]
    effs = [{"spid": rb.shape_id, "kind": "fly", "path": paths[i], "dur": 600,
             "delay": i * 300, "swing": (-8, 0, 8)[i]} for i, rb in enumerate(rboxes)]
    effs.append({"spid": capt.shape_id, "kind": "fade", "dur": 400, "delay": 1300})
    anim.add_group(effs, click=True)
    anim.add_group([{"spid": rboxes[2].shape_id, "kind": "pulse", "dur": 700,
                     "repeat": 3}], click=False)
    for sp in [top] + rboxes + [capt]:
        anim.build_shape(sp.shape_id)


content_slide(6, "1206 \u2013 BIRTH OF THE SULTANATE", [
    ("March 1206: ", "Muhammad Ghori assassinated at Damyak on the Indus \u2014 no son, only ambitious slave generals."),
    ("Three rivals: ", "Yildiz at Ghazni, Qabacha at Multan-Uch, Qutb-ud-din Aibak holding the Indian territories."),
    ("Aibak moved fastest: ", "invited by the nobles and citizens of Lahore, he took charge of Hindustan within months."),
    ("Legitimacy mattered: ", "he used modest titles (Malik, Sipahsalar) until formally freed and recognised (c. 1208)."),
    ("The result: ", "an independent Indian kingdom owing nothing to Ghazni \u2014 the Delhi Sultanate begins here."),
], img="anim/ghori.gif", caption="Damyak, March 1206 \u2014 daggers in the night",
    size=17, gap=13, img_w=3.5, img_h=4.4)

def _coin_shower(s, anim, pic):
    """'Lakh Baksh' — gold coins rain down, endlessly generous."""
    hands = dbox(s, [("LAKH BAKSH", 15, CREAM2, HEAD_FONT, False),
                     ("the giver of lakhs", 11, WHITE, BODY_FONT, True)],
                 9.6, 1.75, 3.1, 1.0, fill=BROWN)
    anim.add_group([{"spid": hands.shape_id, "kind": "zoom", "dur": 500}], click=False)
    anim.build_shape(hands.shape_id)
    xs = [9.75, 10.45, 11.15, 11.85, 12.55]
    for i, x in enumerate(xs):
        coin = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(x), Inches(2.95),
                                  Inches(0.34), Inches(0.34))
        coin.fill.solid(); coin.fill.fore_color.rgb = GOLD
        coin.line.color.rgb = BROWN; coin.line.width = Pt(1)
        coin.shadow.inherit = False
        anim.add_group([{"spid": coin.shape_id, "kind": "motion",
                         "path": "M 0 0 L 0 0.46 E", "dur": 1600 + i * 180,
                         "delay": i * 320, "repeat": "indefinite"}], click=False)
    capt = dlabel(s, "Chroniclers rarely name him without praising his charity",
                  9.3, 6.75, 3.7)
    anim.add_group([{"spid": capt.shape_id, "kind": "fade", "dur": 500}], click=False)
    anim.build_shape(capt.shape_id)


content_slide(7, "QUTB-UD-DIN AIBAK (r. 1206\u20131210)", [
    ("Slave market to throne: ", "sold as a child at Nishapur, educated by a qazi, bought by Ghori \u2014 rose to be his best general."),
    ("Conqueror of the north: ", "consolidated Delhi, Meerut, Ranthambore and Gujarat campaigns after Tarain (1192)."),
    ("'Lakh Baksh' ", "\u2014 the giver of lakhs \u2014 famous above all for open-handed generosity."),
    ("Builder: ", "began the Quwwat-ul-Islam mosque and Qutb Minar at Delhi; Adhai Din ka Jhonpra at Ajmer."),
    ("Sudden end (1210): ", "died in a fall while playing chaugan (polo) at Lahore. His short reign turned a general's command into a kingdom."),
], img="anim/aibak.gif", caption="Lakh Baksh \u2014 gold flows from the throne",
    size=17, gap=13, img_w=3.5, img_h=4.4)

def _foundation_stack(s, anim, pic):
    """Iltutmish builds the state — foundation blocks stack up, one per click."""
    blocks = [("Rivals crushed", "Yildiz \u2022 Qabacha \u2022 Bengal"),
              ("IQTA system", "land revenue = salary"),
              ("The FORTY", "Turkan-i-Chahalgani"),
              ("TANKA + JITAL", "sound money"),
              ("CALIPH 1229", "lawful sultanate")]
    shapes = []
    for i, (a, b) in enumerate(blocks):
        bl = dbox(s, [(a, 12.5, CREAM2, HEAD_FONT, False),
                      (b, 10.5, WHITE, BODY_FONT, False)],
                  9.45, 6.1 - i * 0.92, 3.4, 0.8,
                  fill=BROWN if i % 2 == 0 else BROWN2,
                  shape=MSO_SHAPE.RECTANGLE)
        shapes.append(bl)
    capt = dlabel(s, "Brick by brick \u2014 a state is built", 9.45, 1.35, 3.4)
    for bl in shapes:
        anim.add_group([{"spid": bl.shape_id, "kind": "wipeup", "dur": 450}],
                       click=True)
        anim.build_shape(bl.shape_id)
    anim.add_group([{"spid": capt.shape_id, "kind": "fade", "dur": 400}], click=False)
    anim.build_shape(capt.shape_id)


content_slide(8, "ILTUTMISH (r. 1211\u20131236) \u2013 THE REAL FOUNDER", [
    ("Sold by his own brothers ", "out of jealousy \u2014 rose through sheer ability."),
    ("Defeated every rival: ", "Yildiz (1216), Qabacha (1228); recovered Ranthambore, Gwalior; brought Bengal back."),
    ("Caliph's investiture (1229): ", "Baghdad's recognition made the Sultanate a lawful state in the Islamic world."),
    ("Institution builder: ", "the Forty (Chahalgani), the iqta system, Delhi as permanent capital."),
    ("Currency reform: ", "silver tanka + copper jital \u2014 ancestors of the rupee."),
    ("Boldest decision: ", "nominated his daughter Razia as heir over his sons."),
], img="anim/iltutmish.gif", caption="1229 \u2014 the Caliph\u2019s robe arrives from Baghdad",
    size=16.5, gap=11, img_w=3.5, img_h=4.5)

def _indus_standoff(s, anim, pic):
    """Animated scene: the horde advances to the Indus, Delhi declines, horde retreats."""
    title = dlabel(s, "1221 \u2014 the Indus stand-off", 9.25, 1.45, 3.9, color=BROWN,
                   italic=False, bold=True)
    river = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(11.28), Inches(1.95),
                               Inches(0.14), Inches(3.6))
    river.fill.solid(); river.fill.fore_color.rgb = BLUE
    river.line.fill.background(); river.shadow.inherit = False
    rlab = dlabel(s, "INDUS", 10.95, 5.6, 0.8, size=10, color=BLUE, italic=False, bold=True)
    khan = dbox(s, [("CHINGIZ", 13, CREAM2, HEAD_FONT, False),
                    ("KHAN", 13, CREAM2, HEAD_FONT, False)],
                9.25, 3.0, 1.35, 1.1, fill=DARK)
    delhi = dbox(s, [("DELHI", 13, CREAM2, HEAD_FONT, False),
                     ("Iltutmish", 11, WHITE, BODY_FONT, True)],
                 11.8, 3.0, 1.35, 1.1, fill=BROWN)
    bubble = dbox(s, [("\u201cDelhi's climate", 10.5, DARK, BODY_FONT, False),
                      ("will not suit you\u201d", 10.5, DARK, BODY_FONT, False)],
                  11.0, 4.45, 2.15, 0.75, fill=CREAM2, line_c=BROWN,
                  shape=MSO_SHAPE.ROUNDED_RECTANGLE)
    # scene fades in
    anim.add_group([{"spid": title.shape_id, "kind": "fade", "dur": 400},
                    {"spid": river.shape_id, "kind": "wipe", "dur": 600, "delay": 200},
                    {"spid": rlab.shape_id, "kind": "fade", "dur": 300, "delay": 600},
                    {"spid": khan.shape_id, "kind": "fade", "dur": 400, "delay": 700},
                    {"spid": delhi.shape_id, "kind": "fade", "dur": 400, "delay": 900}],
                   click=False)
    # click 1: the horde advances to the river bank
    anim.add_group([{"spid": khan.shape_id, "kind": "motion",
                     "path": "M 0 0 L 0.047 0 E", "dur": 900}], click=True)
    # click 2: the famous polite refusal
    anim.add_group([{"spid": bubble.shape_id, "kind": "zoom", "dur": 400}], click=True)
    # click 3: the horde turns back — Delhi breathes
    anim.add_group([{"spid": khan.shape_id, "kind": "motion",
                     "path": "M 0 0 L -0.09 -0.01 E", "dur": 1100}], click=True)
    anim.add_group([{"spid": delhi.shape_id, "kind": "pulse", "dur": 600,
                     "repeat": 3}], click=False)
    for sp in (title, river, rlab, khan, delhi, bubble):
        anim.build_shape(sp.shape_id)
    # arrows still whistle along the bottom of the slide
    for t, dur, delay in ((6.35, 2100, 0), (6.62, 1700, 450), (6.88, 1900, 900)):
        ar = prop(s, f"{ASSETS}/arrow.png", -Inches(1.5), Inches(t),
                  Inches(1.35), Inches(0.2))
        anim.add_group([{"spid": ar.shape_id, "kind": "motion",
                         "path": "M 0 0 L 1.3 0.012 E", "dur": dur,
                         "delay": delay, "repeat": "indefinite"}], click=False)


def _ride_through(s, anim, pic):
    """A rider gallops THROUGH the Mongol scene — and arrows fly below."""
    il, it = pic.left, pic.top
    iw, ih = pic.width, pic.height
    hw = Inches(1.0); hh = Emu(int(hw * 932 / 1205))
    horse = prop(s, f"{ASSETS}/horse.png", il - Emu(int(hw * 0.9)),
                 it + ih - Emu(int(hh * 1.15)), hw, hh)
    travel = (iw + hw * 1.2) / SW
    anim.add_group([{"spid": horse.shape_id, "kind": "motion",
                     "path": f"M 0 0 L {travel:.3f} -0.005 E", "dur": 3600,
                     "repeat": "indefinite"}], click=False)
    for t, dur, delay in ((6.35, 2100, 0), (6.62, 1700, 450), (6.88, 1900, 900)):
        ar = prop(s, f"{ASSETS}/arrow.png", -Inches(1.5), Inches(t),
                  Inches(1.35), Inches(0.2))
        anim.add_group([{"spid": ar.shape_id, "kind": "motion",
                         "path": "M 0 0 L 1.3 0.012 E", "dur": dur,
                         "delay": delay, "repeat": "indefinite"}], click=False)


content_slide(9, "THE MONGOL STORM (1221)", [
    ("Chingiz Khan on the Indus: ", "after destroying Khwarazm, the Mongols chased prince Jalal-ud-din to India's doorstep."),
    ("The dilemma: ", "shelter the fugitive prince and invite Chingiz Khan in \u2014 or refuse and look cowardly?"),
    ("Iltutmish's masterstroke: ", "he politely replied that Delhi's climate 'would not suit' the prince \u2014 and quietly moved troops."),
    ("Result: ", "the Mongols withdrew; India escaped the fate of Merv, Nishapur and Baghdad."),
    ("One wrong step in 1221 ", "and the thirty-year-old Sultanate might have ended there."),
], img="anim/mongol.gif", caption="1221 \u2014 the horde waits across the Indus",
    size=17, gap=14, img_w=3.6, img_h=4.3, extras=_ride_through)

def _razia_rise_fall(s, anim, pic):
    """Razia rises on the people's shoulders — and is pulled down by the Forty."""
    throne_y = 2.1
    start_dy = 0.30          # fraction of slide height she rises through
    crown = s.shapes.add_shape(MSO_SHAPE.STAR_5_POINT,
                               Inches(10.95), Inches(throne_y - 0.65),
                               Inches(0.6), Inches(0.6))
    crown.fill.solid(); crown.fill.fore_color.rgb = GOLD
    crown.line.color.rgb = BROWN; crown.line.width = Pt(1)
    crown.shadow.inherit = False
    razia = dbox(s, [("RAZIA", 15, CREAM2, HEAD_FONT, False),
                     ("SULTAN", 12, WHITE, BODY_FONT, True)],
                 10.25, throne_y, 2.0, 1.05, fill=GREEN2)
    up = dlabel(s, "\u25b2  raised by the people of Delhi (1236)",
                9.3, 5.45, 3.9, size=12, color=GREEN2, italic=False, bold=True)
    down = dlabel(s, "\u25bc  pulled down by the Turkish Forty (1240)",
                  9.3, 5.92, 3.9, size=12, color=BROWN, italic=False, bold=True)
    # click 1: she rises to the throne
    anim.add_group([{"spid": up.shape_id, "kind": "fade", "dur": 400},
                    {"spid": razia.shape_id, "kind": "fly",
                     "path": f"M 0 {start_dy} L 0 0 E", "dur": 1100, "delay": 200},
                    {"spid": crown.shape_id, "kind": "zoom", "dur": 400,
                     "delay": 1300}], click=True)
    # click 2: the fall
    anim.add_group([{"spid": down.shape_id, "kind": "fade", "dur": 400},
                    {"spid": razia.shape_id, "kind": "motion",
                     "path": "M 0 0 L 0.012 0.26 E", "dur": 1100, "delay": 300},
                    {"spid": crown.shape_id, "kind": "spin", "deg": 40,
                     "dur": 900, "delay": 300}], click=True)
    capt = dlabel(s, "Not for ruling badly \u2014 for ruling too independently",
                  9.25, 6.5, 4.0)
    anim.add_group([{"spid": capt.shape_id, "kind": "fade", "dur": 500}], click=False)
    for sp in (crown, razia, up, down, capt):
        anim.build_shape(sp.shape_id)


content_slide(10, "RAZIA SULTAN (r. 1236\u20131240)", [
    ("First and only woman ", "to rule from the throne of Delhi \u2014 crowned after Delhi's citizens rose against Ruknuddin Firuz."),
    ("Ruled as a king: ", "abandoned purdah, wore tunic and cap, led armies in person, used the title 'Sultan'."),
    ("Minhaj's verdict: ", "every kingly quality 'except her sex' \u2014 one line that explains her whole struggle."),
    ("Merit over birth: ", "promoted able outsiders like the Abyssinian Yaqut \u2014 enraging the Turkish Forty."),
    ("The fall (1240): ", "betrayed, imprisoned, married the rebel Altunia, marched on Delhi \u2014 killed near Kaithal."),
    ("She fell not for ruling badly ", "\u2014 but for ruling too independently."),
], img="anim/razia.gif", caption="A Sultan, not a Sultana \u2014 leading from the front",
    size=16.5, gap=11, img_w=3.5, img_h=4.5)

def _puppet_show(s, anim, pic):
    """A sultan dangling on the Forty's strings — swinging helplessly."""
    forty = dbox(s, [("THE FORTY", 14, CREAM2, HEAD_FONT, False),
                     ("king-makers", 11, WHITE, BODY_FONT, True)],
                 9.7, 1.7, 3.0, 0.95, fill=DARK)
    from pptx.enum.shapes import MSO_CONNECTOR
    strings = []
    for x in (10.35, 12.05):
        ln = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT,
                                    Inches(x), Inches(2.65), Inches(11.2), Inches(3.9))
        ln.line.color.rgb = GRAY; ln.line.width = Pt(1.25)
        ln.shadow.inherit = False
        strings.append(ln)
    puppet = dbox(s, [("PUPPET", 12.5, CREAM2, HEAD_FONT, False),
                      ("SULTAN", 12.5, CREAM2, HEAD_FONT, False),
                      ("Bahram \u2022 Masud", 10, WHITE, BODY_FONT, False)],
                  10.35, 3.9, 1.7, 1.25, fill=BROWN2)
    capt = dlabel(s, "Crowned, controlled\u2026 and cut loose", 9.6, 5.5, 3.3)
    anim.add_group([{"spid": forty.shape_id, "kind": "zoom", "dur": 500},
                    {"spid": strings[0].shape_id, "kind": "wipe", "dur": 400, "delay": 400},
                    {"spid": strings[1].shape_id, "kind": "wipe", "dur": 400, "delay": 550},
                    {"spid": puppet.shape_id, "kind": "fly",
                     "path": "M 0 -0.12 L 0 0 E", "dur": 600, "delay": 800},
                    {"spid": capt.shape_id, "kind": "fade", "dur": 400, "delay": 1500}],
                   click=True)
    # the puppet keeps swinging on its strings
    anim.add_group([{"spid": puppet.shape_id, "kind": "motion",
                     "path": ("M 0 0 L 0.012 0.004 L 0 0.006 L -0.012 0.004 "
                              "L 0 0 E"), "dur": 2600,
                     "repeat": "indefinite"}], click=False)
    for sp in [forty, puppet, capt] + strings:
        anim.build_shape(sp.shape_id)


content_slide(11, "THE PUPPET YEARS (1240\u20131266)", [
    ("King-makers unleashed: ", "the Forty crowned, controlled and destroyed Bahram Shah (1240\u201342) and Masud Shah (1242\u201346)."),
    ("The cost of chaos: ", "the Mongols sacked Lahore in 1241 \u2014 and Delhi could do nothing."),
    ("Nasiruddin Mahmud (1246\u201366): ", "gentle and pious \u2014 wisely left the real work of government to his deputy, Balban."),
    ("A historian's gift: ", "Minhaj-us-Siraj dedicated his Tabaqat-i-Nasiri to this sultan \u2014 our most important source."),
    ("1266: ", "Mahmud died without a son; the deputy finally took the crown himself."),
], img="anim/puppet.gif", caption="A throne surrounded by whispers",
    size=17, gap=14, img_w=3.5, img_h=4.4)

def _two_pillars(s, anim, pic):
    """The crown rests on two pillars — ceremony and terror."""
    p1 = dbox(s, [("THEATRE OF", 11.5, CREAM2, HEAD_FONT, False),
                  ("MAJESTY", 11.5, CREAM2, HEAD_FONT, False),
                  ("sijda \u2022 paibos", 9.5, WHITE, BODY_FONT, False),
                  ("Nauroz pomp", 9.5, WHITE, BODY_FONT, False)],
              9.55, 3.6, 1.55, 2.5, fill=BROWN, shape=MSO_SHAPE.RECTANGLE)
    p2 = dbox(s, [("BLOOD", 11.5, CREAM2, HEAD_FONT, False),
                  ("AND IRON", 11.5, CREAM2, HEAD_FONT, False),
                  ("bandits crushed", 9.5, WHITE, BODY_FONT, False),
                  ("barid spies", 9.5, WHITE, BODY_FONT, False)],
              11.5, 3.6, 1.55, 2.5, fill=BROWN2, shape=MSO_SHAPE.RECTANGLE)
    beam = dbox(s, [("ZIL-E-ILAHI", 13.5, DARK, HEAD_FONT, False),
                    ("Shadow of God", 10.5, DARK, BODY_FONT, True)],
                9.4, 2.55, 3.8, 0.9, fill=GOLD, line_c=BROWN)
    capt = dlabel(s, "Majesty restored \u2014 at a price", 9.4, 6.25, 3.8)
    # pillars rise one per click, then the golden beam descends onto them
    anim.add_group([{"spid": p1.shape_id, "kind": "wipeup", "dur": 700}], click=True)
    anim.add_group([{"spid": p2.shape_id, "kind": "wipeup", "dur": 700}], click=True)
    anim.add_group([{"spid": beam.shape_id, "kind": "fly",
                     "path": "M 0 -0.22 L 0 0 E", "dur": 800},
                    {"spid": capt.shape_id, "kind": "fade", "dur": 400,
                     "delay": 800}], click=True)
    anim.add_group([{"spid": beam.shape_id, "kind": "pulse", "dur": 700,
                     "repeat": 3}], click=False)
    for sp in (p1, p2, beam, capt):
        anim.build_shape(sp.shape_id)


content_slide(12, "BALBAN (r. 1266\u20131287) \u2013 BLOOD AND IRON", [
    ("Water-carrier to 'Shadow of God': ", "declared the Sultan Zil-e-Ilahi; court modelled on the Persian emperors."),
    ("Theatre of majesty: ", "sijda and paibos, Nauroz pomp, drawn swords \u2014 no laughter in open court."),
    ("Blood and iron: ", "cleared the Mewati bandits, crushed doab rebels, pacified Katehar \u2014 roads safe again."),
    ("Broke the Forty: ", "old comrades sidelined, poisoned or executed; barid spies in every province."),
    ("Bengal (1279): ", "marched there at nearly eighty; an example so harsh Bengal stayed quiet for a generation."),
    ("The price: ", "his heir Prince Muhammad fell to the Mongols (1285); Balban died broken in 1287."),
], img="anim/balban.gif", caption="A court where no one dared to laugh",
    size=16.5, gap=11, img_w=3.5, img_h=4.5)

def _sword_clash(s, anim, pic):
    """Two talwars fly in from the corners and cross with a golden clash burst."""
    sl, st = Inches(9.55), Inches(2.6)
    sw_, sh_ = Inches(2.9), Emu(int(Inches(2.9) * 950 / 1369))
    sword_r = prop(s, f"{ASSETS}/sword_r.png", sl, st, sw_, sh_)   # handle BL, tip TR
    sword_l = prop(s, f"{ASSETS}/sword_l.png", sl, st, sw_, sh_)   # handle BR, tip TL
    star = s.shapes.add_shape(MSO_SHAPE.STAR_8_POINT,
                              Inches(10.55), Inches(3.1), Inches(0.9), Inches(0.9))
    star.fill.solid(); star.fill.fore_color.rgb = GOLD
    star.line.color.rgb = BROWN; star.line.width = Pt(1.25)
    star.shadow.inherit = False
    cap = box(s, Inches(9.35), Inches(5.0), Inches(3.5), Inches(0.6))
    p = cap.text_frame.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
    set_run(p.add_run(), "1290 \u2014 the Khalji swords fall", 12, BODY_FONT, GRAY, italic=True)
    anim.add_group([
        {"spid": sword_r.shape_id, "kind": "fly", "path": "M -0.5 0.35 L 0 0 E",
         "dur": 650, "swing": 25},
        {"spid": sword_l.shape_id, "kind": "fly", "path": "M 0.35 0.35 L 0 0 E",
         "dur": 650, "swing": -25},
        {"spid": star.shape_id, "kind": "zoom", "dur": 300, "delay": 600},
        {"spid": cap.shape_id, "kind": "fade", "dur": 400, "delay": 850},
    ], click=True)
    # the clash star keeps pulsing like ringing steel
    anim.add_group([{"spid": star.shape_id, "kind": "pulse", "dur": 650,
                     "repeat": 4}], click=False)
    for sp in (sword_r, sword_l, star, cap):
        anim.build_shape(sp.shape_id)


content_slide(13, "FALL OF THE DYNASTY (1287\u20131290)", [
    ("Dynasties rarely survive their strongmen: ", "nobles ignored Balban's chosen heir and crowned teenage Kaiqubad."),
    ("Three wasted years: ", "freed from suffocating discipline, Kaiqubad sank into pleasure \u2014 administration collapsed."),
    ("Rise of the Khaljis: ", "the old Turkish party lost ground to veteran commander Jalal-ud-din Khalji."),
    ("1290 \u2013 Khalji Revolution: ", "the paralysed Kaiqubad was killed at Kilokhri; Jalal-ud-din took the throne."),
    ("More than a family change: ", "the Turkish slave elite's monopoly broke forever \u2014 the dynasty fell to the very principle that had raised it: power belongs to the capable."),
], img="anim/duel.gif", caption="1290 \u2014 the Khalji swords fall",
    size=17, gap=14, img_w=3.5, img_h=4.4)

def _state_machine(s, anim, pic):
    """Animated org-chart: Sultan on top, iqta below, revenue & orders flowing."""
    sultan = dbox(s, [("SULTAN", 14, CREAM2, HEAD_FONT, False),
                      ("Delhi", 10.5, WHITE, BODY_FONT, True)],
                  10.1, 1.6, 2.2, 0.95, fill=DARK)
    mins = dbox(s, [("wazir \u2022 ariz \u2022 insha \u2022 qazi", 10.5, WHITE, BODY_FONT, True)],
                9.6, 2.85, 3.2, 0.55, fill=BROWN)
    iqta = dbox(s, [("MUQTIS \u2014 IQTA PROVINCES", 11.5, CREAM2, HEAD_FONT, False),
                    ("collect revenue \u2022 keep troops", 10, WHITE, BODY_FONT, False)],
                9.6, 5.5, 3.2, 0.95, fill=BROWN2)
    up = dbox(s, [("\u25b2", 13, WHITE, BODY_FONT, True)], 10.0, 5.1, 0.45, 0.45,
              fill=GREEN2, line_c=None, shape=MSO_SHAPE.OVAL)
    dn = dbox(s, [("\u25bc", 13, WHITE, BODY_FONT, True)], 11.95, 3.6, 0.45, 0.45,
              fill=BROWN, line_c=None, shape=MSO_SHAPE.OVAL)
    lup = dlabel(s, "revenue", 9.28, 4.35, 1.0, size=10.5, color=GREEN2, italic=False, bold=True)
    ldn = dlabel(s, "orders", 12.35, 4.35, 0.9, size=10.5, color=BROWN, italic=False, bold=True)
    anim.add_group([{"spid": sultan.shape_id, "kind": "zoom", "dur": 450},
                    {"spid": mins.shape_id, "kind": "fade", "dur": 400, "delay": 400},
                    {"spid": iqta.shape_id, "kind": "fade", "dur": 400, "delay": 800},
                    {"spid": lup.shape_id, "kind": "fade", "dur": 300, "delay": 1200},
                    {"spid": ldn.shape_id, "kind": "fade", "dur": 300, "delay": 1300}],
                   click=True)
    # revenue flows up, orders flow down — forever
    anim.add_group([{"spid": up.shape_id, "kind": "motion",
                     "path": "M 0 0 L 0 -0.2 E", "dur": 1800,
                     "repeat": "indefinite"}], click=False)
    anim.add_group([{"spid": dn.shape_id, "kind": "motion",
                     "path": "M 0 0 L 0 0.2 E", "dur": 1800, "delay": 900,
                     "repeat": "indefinite"}], click=False)
    for sp in (sultan, mins, iqta, lup, ldn):
        anim.build_shape(sp.shape_id)


content_slide(14, "ADMINISTRATION", [
    ("The Sultan: ", "absolute in theory \u2014 military power + Islamic legitimacy + (after Balban) a semi-divine aura."),
    ("Great ministries: ", "diwan-i-wizarat (finance), ariz-i-mamalik (army), diwan-i-insha (correspondence), qazi (justice)."),
    ("The iqta system: ", "officers (muqtis) got a territory's land revenue instead of salary \u2014 troops, order, surplus to Delhi."),
    ("Transferable, not hereditary: ", "strong sultans shuffled muqtis so no officer could grow local roots."),
    ("Army & intelligence: ", "heavy cavalry and war elephants; Balban paid the central army directly; barids everywhere."),
    ("Everyday India carried on: ", "village life, caste society, customary law \u2014 taxed but rarely touched."),
], img="anim/tanka.gif", caption="Silver tanka of Iltutmish \u2014 ancestor of the rupee",
    size=16.5, gap=11, img_w=2.9, img_h=2.9, ken=False)

# ---- Architecture slide: the Qutb Minar BUILDS ITSELF, storey by storey
def _minar_build(s, anim, pic):
    ground = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(9.4), Inches(6.45),
                                Inches(3.6), Inches(0.1))
    ground.fill.solid(); ground.fill.fore_color.rgb = GOLD
    ground.line.fill.background(); ground.shadow.inherit = False
    cx = 11.2
    storeys = [(1.55, 1.05, "1199", BROWN), (1.28, 0.95, "", BROWN2),
               (1.04, 0.85, "", BROWN), (0.82, 0.7, "1220", BROWN2),
               (0.62, 0.6, "", BROWN)]
    blocks = []
    y = 6.45
    for w, h, yr, fill in storeys:
        y -= h
        st = dbox(s, [(yr, 10, CREAM2, BODY_FONT, True)] if yr else
                  [("", 6, WHITE, BODY_FONT, False)],
                  cx - w / 2, y, w, h, fill=fill, line_c=GOLD,
                  shape=MSO_SHAPE.ROUND_2_SAME_RECTANGLE)
        blocks.append(st)
    dome = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(cx - 0.17), Inches(y - 0.32),
                              Inches(0.34), Inches(0.3))
    dome.fill.solid(); dome.fill.fore_color.rgb = GOLD
    dome.line.color.rgb = BROWN; dome.line.width = Pt(1)
    dome.shadow.inherit = False
    lab = dlabel(s, "QUTB MINAR \u2014 72.5 m", 9.4, 1.35, 3.6, size=13, color=BROWN,
                 italic=False, bold=True)
    sub = dlabel(s, "begun by Aibak \u2022 finished by Iltutmish", 9.4, 6.65, 3.6,
                 size=11.5)
    anim.add_group([{"spid": ground.shape_id, "kind": "wipe", "dur": 400}], click=False)
    effs = [{"spid": b.shape_id, "kind": "wipeup", "dur": 500, "delay": i * 520}
            for i, b in enumerate(blocks)]
    effs.append({"spid": dome.shape_id, "kind": "zoom", "dur": 350,
                 "delay": len(blocks) * 520})
    effs.append({"spid": lab.shape_id, "kind": "fade", "dur": 400,
                 "delay": len(blocks) * 520 + 300})
    effs.append({"spid": sub.shape_id, "kind": "fade", "dur": 400,
                 "delay": len(blocks) * 520 + 500})
    anim.add_group(effs, click=True)
    for sp in blocks + [ground, dome, lab, sub]:
        anim.build_shape(sp.shape_id)


content_slide(15, "ART AND ARCHITECTURE", [
    ("Quwwat-ul-Islam mosque: ", "Delhi's first great mosque \u2014 built on carved temple pillars; two artistic worlds merging."),
    ("Qutb Minar: ", "begun by Aibak, completed by Iltutmish \u2014 72.5 m, world's tallest brick minaret."),
    ("Tombs: ", "Iltutmish's carved tomb; Sultan Ghari \u2014 earliest Islamic tomb in India."),
    ("Balban's tomb: ", "one of India's first true arches \u2014 pointing toward the Mughal domes to come."),
], img="anim/minar.gif", caption="The tower still rises over Delhi",
    size=17, gap=14, img_w=3.2, img_h=4.7, img_effect="wipeup")

def _legacy_wheel(s, anim, pic):
    """What they left behind — chips radiate from the dynasty's core."""
    core = dbox(s, [("1206\u20131290", 12, CREAM2, HEAD_FONT, False),
                    ("WHAT THEY LEFT", 11, WHITE, BODY_FONT, True)],
                9.75, 1.6, 2.9, 0.9, fill=DARK)
    chips = [("DELHI as capital", BROWN), ("IQTA + ministries", BROWN2),
             ("TANKA currency", BROWN), ("Mongols kept out", BROWN2),
             ("Indo-Islamic culture", BROWN), ("A throne EARNED", GREEN2)]
    shapes = []
    y = 2.75
    for txt, fill in chips:
        c = dbox(s, [(txt, 11.5, WHITE, BODY_FONT, True)], 9.75, y, 2.9, 0.58,
                 fill=fill)
        shapes.append(c)
        y += 0.73
    anim.add_group([{"spid": core.shape_id, "kind": "zoom", "dur": 500}], click=False)
    effs = [{"spid": c.shape_id, "kind": "fly", "path": "M 0.12 0 L 0 0 E",
             "dur": 380, "delay": i * 300} for i, c in enumerate(shapes)]
    anim.add_group(effs, click=True)
    for sp in [core] + shapes:
        anim.build_shape(sp.shape_id)


content_slide(16, "LEGACY AND SIGNIFICANCE", [
    ("Political: ", "made Delhi the imperial centre of India \u2014 a status it has never really lost."),
    ("Administrative: ", "iqta, ministries, barid network, standing army \u2014 scaffolding for Khaljis, Tughlaqs, even Mughals."),
    ("Economic: ", "the tanka\u2013jital currency anchored north Indian commerce for generations."),
    ("Strategic: ", "its defence of the north-west kept the Mongol catastrophe out of India."),
    ("Cultural: ", "Amir Khusrau's poetry, the Chishti saints, and the start of the Indo-Islamic synthesis."),
    ("A radical idea: ", "a slave could become sultan; a woman could rule \u2014 the throne of Delhi could be earned."),
], img="anim/legacy.gif", caption="What they built still stands",
    size=16.5, gap=11, img_w=3.3, img_h=4.5)

# ---- Conclusion
s, anim = add_slide()
side_bar(s); footer(s, 17)
heading(s, anim, "CONCLUSION")
bullets(s, anim, [
    ("An empire founded by men who had once been merchandise ", "\u2014 the strangest arc in medieval Indian history."),
    ("Aibak ", "turned a conqueror's garrisons into a kingdom."),
    ("Iltutmish ", "gave it law, money and legitimacy \u2014 and saved it from Chingiz Khan with one evasive letter."),
    ("Razia ", "showed how far ability could carry a person; her fate showed where the limits lay."),
    ("Balban ", "rebuilt the crown's majesty with ceremony and cruelty \u2014 and held the frontier at the cost of his son."),
    ("Eighty-four years ", "\u2014 an improvised occupation became a settled state with a capital, a currency and a culture. The dynasties that followed built higher, but on this foundation."),
], Inches(0.8), Inches(1.45), SW - Inches(1.7), Inches(4.9), size=17, gap=11)
ty = box(s, Inches(0.8), SH - Inches(1.1), SW - Inches(1.7), Inches(0.75))
p = ty.text_frame.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
r = p.add_run(); set_run(r, "THANK YOU", 34, HEAD_FONT, BROWN); r.font.underline = True
anim.add_group([{"spid": ty.shape_id, "kind": "zoom", "dur": 700}], click=True)
anim.add_group([{"spid": ty.shape_id, "kind": "pulse", "dur": 800, "repeat": 3}],
               click=False)
anim.build_shape(ty.shape_id)
# a last rider gallops off into history
running_horse(s, anim, Inches(5.1), w=1.35, dur=6000)
anim.apply()

# ====================================================================
#  SLIDE 18 — THE TEDDY BEAR SAYS GOODBYE (animated)
# ====================================================================
s, anim = add_slide()
side_bar(s); footer(s, 18)
heading(s, anim, "THANK YOU, MATES!")
picture(s, anim, f"{ASSETS}/anim/teddy.gif", Inches(4.57), Inches(1.42),
        Inches(4.2), Inches(5.25),
        "That's the story of the Slave Dynasty \u2014 thank you mates!",
        effect="zoom", effect_dur=700, ken=False)
anim.apply()

OUT = "/home/user/SIH/assignment/Slave_Dynasty_Mamluk_Presentation.pptx"
prs.save(OUT)
print("saved", OUT, "| slides:", len(prs.slides._sldIdLst))
