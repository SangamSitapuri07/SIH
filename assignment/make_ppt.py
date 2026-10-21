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
        tgt = self._tgt(spid, prg)
        preset = {"fade": 10, "wipe": 22, "zoom": 53}[kind]
        i1, i2, i3 = next(self._id), next(self._id), next(self._id)
        inner = (
            f'<p:set><p:cBhvr><p:cTn id="{i2}" dur="1" fill="hold">'
            f'<p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn>{tgt}'
            f'<p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst>'
            f'</p:cBhvr><p:to><p:strVal val="visible"/></p:to></p:set>'
        )
        if kind == "wipe":
            inner += (f'<p:animEffect transition="in" filter="wipe(down)">'
                      f'<p:cBhvr><p:cTn id="{i3}" dur="{dur}"/>{tgt}</p:cBhvr></p:animEffect>')
        else:
            inner += (f'<p:animEffect transition="in" filter="fade">'
                      f'<p:cBhvr><p:cTn id="{i3}" dur="{dur}"/>{tgt}</p:cBhvr></p:animEffect>')
        if kind == "zoom":
            i4 = next(self._id)
            inner += (
                f'<p:animScale><p:cBhvr><p:cTn id="{i4}" dur="{dur}" fill="hold"/>'
                f'{tgt}</p:cBhvr><p:from x="20000" y="20000"/>'
                f'<p:to x="100000" y="100000"/></p:animScale>'
            )
        return (
            f'<p:par><p:cTn id="{i1}" presetID="{preset}" presetClass="entr" '
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


def picture(slide, anim, path, l, t, w, h, caption=None, zoom=True):
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
    effs = [{"spid": sp.shape_id, "kind": "zoom" if zoom else "fade", "dur": 600,
             "delay": 150 * i} for i, sp in enumerate(shapes)]
    anim.add_group(effs, click=False)
    for sp in shapes:
        anim.build_shape(sp.shape_id)
    return pic


# content slide with picture on the right
def content_slide(n, title, items, img=None, caption=None, size=17, gap=12,
                  img_w=3.3, img_h=4.3):
    s, anim = add_slide()
    side_bar(s); footer(s, n)
    heading(s, anim, title)
    if img:
        iw, ih = Inches(img_w), Inches(img_h)
        il = SW - iw - Inches(0.55)
        it = Inches(1.55)
        picture(s, anim, f"{ASSETS}/{img}", il, it, iw, ih, caption)
        tw = il - Inches(1.05)
    else:
        tw = SW - Inches(1.7)
    bullets(s, anim, items, Inches(0.8), Inches(1.5), tw, Inches(5.6), size=size, gap=gap)
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
#  SLIDE 3 — INTRODUCTION  (map)
# ====================================================================
content_slide(3, "INTRODUCTION", [
    ("Rulers of Delhi, 1206\u20131290 CE ", "\u2014 the first dynasty of the Delhi Sultanate, founded after Muhammad Ghori's death."),
    ("'Mamluk' ", "is Arabic for 'one who is owned'. Every sultan of this line was a former slave or a slave's descendant."),
    ("Nobody ruled as a slave ", "\u2014 each ruler was legally freed (manumitted) before taking the throne."),
    ("Really three families: ", "the houses of Aibak, Iltutmish and Balban, one after another."),
    ("Why it matters: ", "it laid the foundation of the Delhi Sultanate \u2014 Delhi as capital, the tanka coin, the iqta system, the Qutb Minar \u2014 shaping north India for 300 years."),
], img="map.jpg", caption="The Mamluk Sultanate, c. 1250", size=18, gap=14, img_w=3.4, img_h=3.2)

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
anim.apply()

# ====================================================================
#  CONTENT SLIDES
# ====================================================================
content_slide(5, "WHO WERE THE MAMLUKS?", [
    ("Elite military slaves ", "(bandagan) \u2014 Turkic boys bought in Central Asian markets, trained in war, horsemanship and court manners."),
    ("Loyalty by design: ", "cut off from family and clan, a slave soldier had nobody except his master."),
    ("Promotion purely on merit ", "\u2014 a talented slave could rise to general, governor\u2026 and eventually king."),
    ("Not plantation slavery: ", "they ate well, commanded armies, married into noble families \u2014 apprenticeship plus bonded loyalty."),
    ("Ghori's 'sons': ", "asked about having no heir, Ghori said his thousands of Turkish slaves would carry his name \u2014 and they did."),
], img="mamluk_cavalry.jpg", caption="Turkic mamluk cavalry (artistic reconstruction)",
    size=17, gap=13)

content_slide(6, "1206 \u2013 BIRTH OF THE SULTANATE", [
    ("March 1206: ", "Muhammad Ghori assassinated at Damyak on the Indus \u2014 no son, only ambitious slave generals."),
    ("Three rivals: ", "Yildiz at Ghazni, Qabacha at Multan-Uch, Qutb-ud-din Aibak holding the Indian territories."),
    ("Aibak moved fastest: ", "invited by the nobles and citizens of Lahore, he took charge of Hindustan within months."),
    ("Legitimacy mattered: ", "he used modest titles (Malik, Sipahsalar) until formally freed and recognised (c. 1208)."),
    ("The result: ", "an independent Indian kingdom owing nothing to Ghazni \u2014 the Delhi Sultanate begins here."),
], img="map.jpg", caption="The new state and its frontiers", size=17, gap=13, img_h=3.2)

content_slide(7, "QUTB-UD-DIN AIBAK (r. 1206\u20131210)", [
    ("Slave market to throne: ", "sold as a child at Nishapur, educated by a qazi, bought by Ghori \u2014 rose to be his best general."),
    ("Conqueror of the north: ", "consolidated Delhi, Meerut, Ranthambore and Gujarat campaigns after Tarain (1192)."),
    ("'Lakh Baksh' ", "\u2014 the giver of lakhs \u2014 famous above all for open-handed generosity."),
    ("Builder: ", "began the Quwwat-ul-Islam mosque and Qutb Minar at Delhi; Adhai Din ka Jhonpra at Ajmer."),
    ("Sudden end (1210): ", "died in a fall while playing chaugan (polo) at Lahore. His short reign turned a general's command into a kingdom."),
], img="quwwat.jpg", caption="Quwwat-ul-Islam mosque \u2014 begun by Aibak", size=17, gap=13)

content_slide(8, "ILTUTMISH (r. 1211\u20131236) \u2013 THE REAL FOUNDER", [
    ("Sold by his own brothers ", "out of jealousy \u2014 rose through sheer ability."),
    ("Defeated every rival: ", "Yildiz (1216), Qabacha (1228); recovered Ranthambore, Gwalior; brought Bengal back."),
    ("Caliph's investiture (1229): ", "Baghdad's recognition made the Sultanate a lawful state in the Islamic world."),
    ("Institution builder: ", "the Forty (Chahalgani), the iqta system, Delhi as permanent capital."),
    ("Currency reform: ", "silver tanka + copper jital \u2014 ancestors of the rupee."),
    ("Boldest decision: ", "nominated his daughter Razia as heir over his sons."),
], img="iltutmish_tomb.jpg", caption="Carved walls of Iltutmish's tomb, Qutb complex",
    size=16.5, gap=11)

content_slide(9, "THE MONGOL STORM (1221)", [
    ("Chingiz Khan on the Indus: ", "after destroying Khwarazm, the Mongols chased prince Jalal-ud-din to India's doorstep."),
    ("The dilemma: ", "shelter the fugitive prince and invite Chingiz Khan in \u2014 or refuse and look cowardly?"),
    ("Iltutmish's masterstroke: ", "he politely replied that Delhi's climate 'would not suit' the prince \u2014 and quietly moved troops."),
    ("Result: ", "the Mongols withdrew; India escaped the fate of Merv, Nishapur and Baghdad."),
    ("One wrong step in 1221 ", "and the thirty-year-old Sultanate might have ended there."),
], img="genghis.jpg", caption="Chingiz Khan \u2014 Yuan-era portrait", size=17, gap=14,
    img_w=2.9, img_h=3.4)

content_slide(10, "RAZIA SULTAN (r. 1236\u20131240)", [
    ("First and only woman ", "to rule from the throne of Delhi \u2014 crowned after Delhi's citizens rose against Ruknuddin Firuz."),
    ("Ruled as a king: ", "abandoned purdah, wore tunic and cap, led armies in person, used the title 'Sultan'."),
    ("Minhaj's verdict: ", "every kingly quality 'except her sex' \u2014 one line that explains her whole struggle."),
    ("Merit over birth: ", "promoted able outsiders like the Abyssinian Yaqut \u2014 enraging the Turkish Forty."),
    ("The fall (1240): ", "betrayed, imprisoned, married the rebel Altunia, marched on Delhi \u2014 killed near Kaithal."),
    ("She fell not for ruling badly ", "\u2014 but for ruling too independently."),
], img="razia.jpg", caption="Razia Sultana on horseback \u2014 19th-c. painting",
    size=16.5, gap=11, img_w=2.9, img_h=3.7)

content_slide(11, "THE PUPPET YEARS (1240\u20131266)", [
    ("King-makers unleashed: ", "the Forty crowned, controlled and destroyed Bahram Shah (1240\u201342) and Masud Shah (1242\u201346)."),
    ("The cost of chaos: ", "the Mongols sacked Lahore in 1241 \u2014 and Delhi could do nothing."),
    ("Nasiruddin Mahmud (1246\u201366): ", "gentle and pious \u2014 wisely left the real work of government to his deputy, Balban."),
    ("A historian's gift: ", "Minhaj-us-Siraj dedicated his Tabaqat-i-Nasiri to this sultan \u2014 our most important source."),
    ("1266: ", "Mahmud died without a son; the deputy finally took the crown himself."),
], size=18, gap=15)

content_slide(12, "BALBAN (r. 1266\u20131287) \u2013 BLOOD AND IRON", [
    ("Water-carrier to 'Shadow of God': ", "declared the Sultan Zil-e-Ilahi; court modelled on the Persian emperors."),
    ("Theatre of majesty: ", "sijda and paibos, Nauroz pomp, drawn swords \u2014 no laughter in open court."),
    ("Blood and iron: ", "cleared the Mewati bandits, crushed doab rebels, pacified Katehar \u2014 roads safe again."),
    ("Broke the Forty: ", "old comrades sidelined, poisoned or executed; barid spies in every province."),
    ("Bengal (1279): ", "marched there at nearly eighty; an example so harsh Bengal stayed quiet for a generation."),
    ("The price: ", "his heir Prince Muhammad fell to the Mongols (1285); Balban died broken in 1287."),
], img="balban_tomb.jpg", caption="Balban's tomb \u2014 one of India's first true arches",
    size=16.5, gap=11)

content_slide(13, "FALL OF THE DYNASTY (1287\u20131290)", [
    ("Dynasties rarely survive their strongmen: ", "nobles ignored Balban's chosen heir and crowned teenage Kaiqubad."),
    ("Three wasted years: ", "freed from suffocating discipline, Kaiqubad sank into pleasure \u2014 administration collapsed."),
    ("Rise of the Khaljis: ", "the old Turkish party lost ground to veteran commander Jalal-ud-din Khalji."),
    ("1290 \u2013 Khalji Revolution: ", "the paralysed Kaiqubad was killed at Kilokhri; Jalal-ud-din took the throne."),
    ("More than a family change: ", "the Turkish slave elite's monopoly broke forever \u2014 the dynasty fell to the very principle that had raised it: power belongs to the capable."),
], size=18, gap=15)

content_slide(14, "ADMINISTRATION", [
    ("The Sultan: ", "absolute in theory \u2014 military power + Islamic legitimacy + (after Balban) a semi-divine aura."),
    ("Great ministries: ", "diwan-i-wizarat (finance), ariz-i-mamalik (army), diwan-i-insha (correspondence), qazi (justice)."),
    ("The iqta system: ", "officers (muqtis) got a territory's land revenue instead of salary \u2014 troops, order, surplus to Delhi."),
    ("Transferable, not hereditary: ", "strong sultans shuffled muqtis so no officer could grow local roots."),
    ("Army & intelligence: ", "heavy cavalry and war elephants; Balban paid the central army directly; barids everywhere."),
    ("Everyday India carried on: ", "village life, caste society, customary law \u2014 taxed but rarely touched."),
], img="tanka.jpg", caption="Silver tanka of Iltutmish \u2014 ancestor of the rupee",
    size=16.5, gap=11, img_w=2.9, img_h=2.9)

# ---- Architecture slide (two pictures)
s, anim = add_slide()
side_bar(s); footer(s, 15)
heading(s, anim, "ART AND ARCHITECTURE")
bullets(s, anim, [
    ("Quwwat-ul-Islam mosque: ", "Delhi's first great mosque \u2014 built on carved temple pillars; two artistic worlds merging."),
    ("Qutb Minar: ", "begun by Aibak, completed by Iltutmish \u2014 72.5 m, world's tallest brick minaret."),
    ("Tombs: ", "Iltutmish's carved tomb; Sultan Ghari \u2014 earliest Islamic tomb in India."),
    ("Balban's tomb: ", "one of India's first true arches \u2014 pointing toward the Mughal domes to come."),
], Inches(0.75), Inches(1.5), Inches(5.7), Inches(5.3), size=16, gap=13)
picture(s, anim, f"{ASSETS}/quwwat.jpg", Inches(6.7), Inches(1.5), Inches(3.05), Inches(4.2),
        caption=None)
picture(s, anim, f"{ASSETS}/qutb_minar.jpg", Inches(9.95), Inches(1.5), Inches(3.05), Inches(4.2),
        caption=None)
cap = box(s, Inches(6.7), Inches(5.8), Inches(6.3), Inches(0.5))
p = cap.text_frame.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
set_run(p.add_run(), "Quwwat-ul-Islam corridor  \u2022  Qutb Minar", 12, BODY_FONT, GRAY, italic=True)
anim.add_group([{"spid": cap.shape_id, "kind": "fade", "dur": 400}], click=False)
anim.build_shape(cap.shape_id)
anim.apply()

content_slide(16, "LEGACY AND SIGNIFICANCE", [
    ("Political: ", "made Delhi the imperial centre of India \u2014 a status it has never really lost."),
    ("Administrative: ", "iqta, ministries, barid network, standing army \u2014 scaffolding for Khaljis, Tughlaqs, even Mughals."),
    ("Economic: ", "the tanka\u2013jital currency anchored north Indian commerce for generations."),
    ("Strategic: ", "its defence of the north-west kept the Mongol catastrophe out of India."),
    ("Cultural: ", "Amir Khusrau's poetry, the Chishti saints, and the start of the Indo-Islamic synthesis."),
    ("A radical idea: ", "a slave could become sultan; a woman could rule \u2014 the throne of Delhi could be earned."),
], img="qutb_minar.jpg", caption="The dynasty's signature on Delhi's skyline",
    size=16.5, gap=11, img_w=2.9, img_h=4.5)

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
anim.build_shape(ty.shape_id)
anim.apply()

OUT = "/home/user/SIH/assignment/Slave_Dynasty_Mamluk_Presentation.pptx"
prs.save(OUT)
print("saved", OUT, "| slides:", len(prs.slides._sldIdLst))
