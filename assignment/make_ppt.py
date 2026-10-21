#!/usr/bin/env python3
"""Slave Dynasty (Mamluk) presentation — theme matched to the assignment PDF:
cream background, brown Bernard MT Condensed headings, Times New Roman body,
LPU seal on the title slide."""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from pptx.oxml.ns import qn
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

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
SW, SH = prs.slide_width, prs.slide_height
blank = prs.slide_layouts[6]


def add_slide():
    s = prs.slides.add_slide(blank)
    bg = s.background
    bg.fill.solid()
    bg.fill.fore_color.rgb = CREAM
    return s


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
    bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, Inches(0.22), SH)
    bar.fill.solid()
    bar.fill.fore_color.rgb = BROWN
    bar.line.fill.background()
    bar.shadow.inherit = False
    bar2 = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.22), 0, Inches(0.07), SH)
    bar2.fill.solid()
    bar2.fill.fore_color.rgb = GOLD
    bar2.line.fill.background()
    bar2.shadow.inherit = False


def footer(slide, n, total):
    tb = box(slide, SW - Inches(1.6), SH - Inches(0.45), Inches(1.3), Inches(0.3))
    p = tb.text_frame.paragraphs[0]
    p.alignment = PP_ALIGN.RIGHT
    set_run(p.add_run(), f"{n} | Page", 11, BODY_FONT, GRAY)


def heading(slide, text, size=38):
    tb = box(slide, Inches(0.65), Inches(0.35), SW - Inches(1.3), Inches(1.0))
    p = tb.text_frame.paragraphs[0]
    r = p.add_run()
    set_run(r, text, size, HEAD_FONT, BROWN, bold=False)
    r.font.underline = True
    return tb


def bullets(slide, items, l, t, w, h, size=17, gap=10, bullet_color=BROWN):
    tb = box(slide, l, t, w, h)
    tf = tb.text_frame
    first = True
    for item in items:
        p = tf.paragraphs[0] if first else tf.add_paragraph()
        first = False
        p.space_after = Pt(gap)
        p.alignment = PP_ALIGN.LEFT
        rb = p.add_run()
        set_run(rb, "\u27a2  ", size, "Arial", bullet_color, bold=True)
        # item may be (bold_prefix, rest) or plain string
        if isinstance(item, tuple):
            r1 = p.add_run()
            set_run(r1, item[0], size, BODY_FONT, DARK, bold=True)
            r2 = p.add_run()
            set_run(r2, item[1], size, BODY_FONT, DARK)
        else:
            r = p.add_run()
            set_run(r, item, size, BODY_FONT, DARK)
    return tb


def pic_fit(slide, path, l, t, w, h):
    """Place image covering box (center-crop feel via aspect fit)."""
    iw, ih = Image.open(path).size
    box_ratio = w / h
    img_ratio = iw / ih
    if img_ratio > box_ratio:
        nh = h
        nw = int(h * img_ratio)
    else:
        nw = w
        nh = int(w / img_ratio)
    pic = slide.shapes.add_picture(path, l + int((w - nw) / 2), t + int((h - nh) / 2), nw, nh)
    # crop to box
    cl = (nw - w) / 2 / nw
    ct = (nh - h) / 2 / nh
    pic.crop_left = cl
    pic.crop_right = cl
    pic.crop_top = ct
    pic.crop_bottom = ct
    pic.left, pic.top, pic.width, pic.height = l, t, w, h
    return pic


TOTAL = 16
n = 0

# ============================================================ 1. TITLE
s = add_slide()
n += 1
# top & bottom brown bands
band = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, SW, Inches(0.18))
band.fill.solid(); band.fill.fore_color.rgb = BROWN; band.line.fill.background(); band.shadow.inherit = False
band = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, SH - Inches(0.18), SW, Inches(0.18))
band.fill.solid(); band.fill.fore_color.rgb = BROWN; band.line.fill.background(); band.shadow.inherit = False

tb = box(s, Inches(0.5), Inches(0.45), SW - Inches(1.0), Inches(1.5))
p = tb.text_frame.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
r = p.add_run(); set_run(r, "LOVELY PROFESSIONAL UNIVERSITY", 40, HEAD_FONT, DARK); r.font.underline = True
p2 = tb.text_frame.add_paragraph(); p2.alignment = PP_ALIGN.CENTER; p2.space_before = Pt(6)
r = p2.add_run(); set_run(r, "SCHOOL OF LAW", 26, HEAD_FONT, DARK); r.font.underline = True

seal_w = Inches(1.75)
s.shapes.add_picture(f"{ASSETS}/lpu_seal.jpg", int((SW - seal_w) / 2), Inches(2.0), seal_w, seal_w * (133.45 / 132.0))

tb = box(s, Inches(0.5), Inches(3.95), SW - Inches(1.0), Inches(1.6))
p = tb.text_frame.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
set_run(p.add_run(), "CA \u2013 01 HISTORY (SSC231)", 22, HEAD_FONT, BROWN)
p2 = tb.text_frame.add_paragraph(); p2.alignment = PP_ALIGN.CENTER; p2.space_before = Pt(4)
r = p2.add_run(); set_run(r, "SLAVE DYNASTY (MAMLUK DYNASTY)", 36, HEAD_FONT, BROWN); r.font.underline = True
p3 = tb.text_frame.add_paragraph(); p3.alignment = PP_ALIGN.CENTER; p3.space_before = Pt(4)
set_run(p3.add_run(), "Delhi Sultanate \u2022 1206 \u2013 1290 CE", 16, BODY_FONT, DARK, italic=True)

tb = box(s, Inches(1.6), Inches(5.65), Inches(5.2), Inches(1.6))
tf = tb.text_frame
p = tf.paragraphs[0]
set_run(p.add_run(), "Submitted by :", 20, HEAD_FONT, DARK)
for line in ["Sangam Sitapuri", "Reg. no. \u2013 RK202406B65", "Course \u2013 SSC231"]:
    pp = tf.add_paragraph(); pp.space_before = Pt(2)
    set_run(pp.add_run(), line, 15, BODY_FONT, DARK, bold=True)

tb = box(s, Inches(7.4), Inches(5.65), Inches(4.6), Inches(1.6))
tf = tb.text_frame
p = tf.paragraphs[0]
set_run(p.add_run(), "Submitted to :", 20, HEAD_FONT, DARK)
pp = tf.add_paragraph(); pp.space_before = Pt(2)
r = pp.add_run(); set_run(r, "Dr. Vandana Arya", 15, BODY_FONT, DARK, bold=True); r.font.underline = True

# ============================================================ 2. CONTENTS
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
tb = box(s, Inches(0.65), Inches(0.35), SW - Inches(1.3), Inches(1.0))
p = tb.text_frame.paragraphs[0]
r = p.add_run(); set_run(r, "TABLE OF CONTENT", 40, HEAD_FONT, GREEN); r.font.underline = True
items_l = [
    "Introduction", "Who Were the Mamluks?", "1206 \u2013 Birth of the Sultanate",
    "Qutb-ud-din Aibak", "Iltutmish \u2013 The Real Founder", "The Mongol Storm (1221)",
    "Razia Sultan",
]
items_r = [
    "The Puppet Years (1240\u201366)", "Balban \u2013 Blood and Iron", "Fall of the Dynasty (1290)",
    "Administration", "Art and Architecture", "Legacy and Significance", "Conclusion",
]
for items, lx in ((items_l, Inches(0.95)), (items_r, Inches(7.0))):
    tb = box(s, lx, Inches(1.7), Inches(5.6), Inches(5.3))
    tf = tb.text_frame
    first = True
    start = 1 if items is items_l else 8
    for i, it in enumerate(items):
        p = tf.paragraphs[0] if first else tf.add_paragraph()
        first = False
        p.space_after = Pt(14)
        set_run(p.add_run(), f"{start + i:02d}.  ", 19, BODY_FONT, BROWN, bold=True)
        set_run(p.add_run(), it, 19, BODY_FONT, DARK, bold=True)

# ============================================================ 3. INTRODUCTION
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "INTRODUCTION")
bullets(s, [
    ("Rulers of Delhi, 1206\u20131290 CE ", "\u2014 the first dynasty of the Delhi Sultanate, founded after Muhammad Ghori's death."),
    ("'Mamluk' ", "is Arabic for 'one who is owned'. Every sultan of this line was either a former slave or descended from one."),
    ("Nobody ruled as a slave ", "\u2014 each ruler was legally freed (manumitted) before taking the throne. The popular name 'Slave Dynasty' is catchy but slightly misleading."),
    ("Really three families, not one: ", "the houses of Qutb-ud-din Aibak, Iltutmish and Balban, one after another."),
    ("Why it matters: ", "it laid the foundation of the Delhi Sultanate \u2014 Delhi as capital, the tanka coin, the iqta system, the Qutb Minar \u2014 shaping north India for 300 years."),
], Inches(0.8), Inches(1.6), SW - Inches(1.7), Inches(5.3), size=19, gap=16)

# ============================================================ 4. WHO WERE THE MAMLUKS
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "WHO WERE THE MAMLUKS?")
bullets(s, [
    ("Elite military slaves ", "(bandagan) \u2014 Turkic boys bought in Central Asian markets, converted, and trained in war, horsemanship and court manners."),
    ("Loyalty by design: ", "cut off from family and clan, a slave soldier had nobody except his master \u2014 which made him the most trusted officer."),
    ("Promotion purely on merit ", "\u2014 a talented slave could rise to general, governor\u2026 and eventually king."),
    ("Not plantation slavery: ", "they ate well, commanded armies and married into noble families. Slavery here was really apprenticeship plus bonded loyalty."),
    ("Ghori's 'sons': ", "asked about having no heir, Muhammad Ghori reportedly said his thousands of Turkish slaves would carry his name \u2014 and they did."),
], Inches(0.8), Inches(1.6), SW - Inches(1.7), Inches(5.3), size=19, gap=16)

# ============================================================ 5. 1206
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "1206 \u2013 BIRTH OF THE SULTANATE")
bullets(s, [
    ("March 1206: ", "Muhammad Ghori assassinated at Damyak on the Indus \u2014 no son, only an empire and ambitious slave generals."),
    ("Three rivals emerged: ", "Yildiz at Ghazni, Qabacha at Multan-Uch, and Qutb-ud-din Aibak holding the Indian territories."),
    ("Aibak moved fastest: ", "invited by the nobles and citizens of Lahore, he took charge of Hindustan within months."),
    ("Legitimacy mattered: ", "he used the modest titles Malik and Sipahsalar until formally manumitted and recognised (c. 1208)."),
    ("The result: ", "an independent Indian kingdom, owing nothing to Ghazni \u2014 the Delhi Sultanate begins here."),
], Inches(0.8), Inches(1.6), SW - Inches(1.7), Inches(5.3), size=19, gap=16)

# ============================================================ 6. AIBAK
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "QUTB-UD-DIN AIBAK (r. 1206\u20131210)")
bullets(s, [
    ("From slave market to throne: ", "sold as a child at Nishapur, educated by a qazi, finally bought by Muhammad Ghori \u2014 rose to be his best general."),
    ("Real conqueror of the north: ", "consolidated Delhi, Meerut, Ranthambore and Gujarat campaigns after Tarain (1192)."),
    ("'Lakh Baksh' ", "\u2014 the giver of lakhs. Famous for open-handed generosity; chroniclers rarely mention him without praising it."),
    ("Builder: ", "began the Quwwat-ul-Islam mosque and the Qutb Minar at Delhi, and Adhai Din ka Jhonpra at Ajmer."),
    ("Sudden end: ", "died in 1210 in a fall while playing chaugan (polo) at Lahore; buried there. His short reign turned a general's command into a kingdom."),
], Inches(0.8), Inches(1.6), SW - Inches(1.7), Inches(5.3), size=19, gap=15)

# ============================================================ 7. ILTUTMISH
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "ILTUTMISH (r. 1211\u20131236) \u2013 THE REAL FOUNDER")
bullets(s, [
    ("Sold by his own brothers ", "out of jealousy \u2014 a rise through sheer ability that reminded chroniclers of the story of Yusuf."),
    ("Defeated every rival: ", "crushed Yildiz at Tarain (1216), broke Qabacha (1228), recovered Ranthambore and Gwalior, brought Bengal back."),
    ("Caliph's investiture (1229): ", "formal recognition from Baghdad made the Sultanate a lawful state in the eyes of the Islamic world."),
    ("Institution builder: ", "the corps of Forty (Turkan-i-Chahalgani), the iqta revenue system, and Delhi as permanent capital."),
    ("Currency reform: ", "silver tanka (~175 grains) and copper jital \u2014 standard coins of the Sultanate, ancestors of the rupee."),
    ("Boldest decision: ", "nominated his daughter Razia as heir, judging his sons incompetent."),
], Inches(0.8), Inches(1.55), SW - Inches(1.7), Inches(5.5), size=18, gap=13)

# ============================================================ 8. MONGOL STORM
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "THE MONGOL STORM (1221)")
bullets(s, [
    ("Chingiz Khan on the Indus: ", "after destroying the Khwarazmian empire, the Mongols chased prince Jalal-ud-din to India's doorstep."),
    ("The dilemma: ", "the fugitive prince asked Delhi for asylum. Sheltering him meant inviting Chingiz Khan in; refusing looked cowardly."),
    ("Iltutmish's masterstroke: ", "with perfect politeness he replied that Delhi's climate 'would not suit' the prince \u2014 and quietly moved troops."),
    ("Result: ", "Jalal-ud-din left, the Mongols withdrew, and India escaped the fate of Merv, Nishapur and Baghdad."),
    ("One wrong step in 1221 ", "and the thirty-year-old Sultanate \u2014 and much of Indian history \u2014 might have ended there."),
], Inches(0.8), Inches(1.6), SW - Inches(1.7), Inches(5.3), size=19, gap=16)

# ============================================================ 9. RAZIA
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "RAZIA SULTAN (r. 1236\u20131240)")
bullets(s, [
    ("First and only woman ", "ever to rule from the throne of Delhi \u2014 crowned after the citizens of Delhi themselves rose against Ruknuddin Firuz."),
    ("Ruled as a king: ", "abandoned purdah, wore tunic and cap, led armies in person, used the title 'Sultan' \u2014 no feminine variant."),
    ("Minhaj-us-Siraj's verdict: ", "she had every kingly quality 'except her sex' \u2014 one line that explains her whole struggle."),
    ("Merit over birth: ", "promoted able outsiders like the Abyssinian officer Yaqut \u2014 which enraged the Turkish nobles of the Forty."),
    ("The fall (1240): ", "betrayed, imprisoned at Bhatinda, married the rebel Altunia, marched on Delhi \u2014 defeated and killed near Kaithal."),
    ("She fell not because she ruled badly, ", "but because she ruled too independently."),
], Inches(0.8), Inches(1.55), SW - Inches(1.7), Inches(5.5), size=18, gap=13)

# ============================================================ 10. PUPPET YEARS
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "THE PUPPET YEARS (1240\u20131266)")
bullets(s, [
    ("King-makers unleashed: ", "the Forty made and unmade sultans at will \u2014 Bahram Shah (1240\u201342) and Masud Shah (1242\u201346) were crowned, controlled, and destroyed."),
    ("The cost of chaos: ", "while the court devoured itself, the Mongols sacked Lahore in 1241 \u2014 and Delhi could do nothing."),
    ("Nasiruddin Mahmud (1246\u201366): ", "gentle, pious, famously simple \u2014 wisely left the real work of government to his deputy, Balban."),
    ("A historian's gift: ", "Minhaj-us-Siraj dedicated his Tabaqat-i-Nasiri to this sultan \u2014 our single most important source for the period."),
    ("1266: ", "Mahmud died without a son; the deputy who had run the state for years finally took the crown himself."),
], Inches(0.8), Inches(1.6), SW - Inches(1.7), Inches(5.3), size=19, gap=15)

# ============================================================ 11. BALBAN
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "BALBAN (r. 1266\u20131287) \u2013 BLOOD AND IRON")
bullets(s, [
    ("Water-carrier to 'Shadow of God': ", "a former slave who declared the Sultan Zil-e-Ilahi and modelled his court on the Persian emperors."),
    ("Theatre of majesty: ", "sijda and paibos, Nauroz ceremony, drawn swords, no laughter in open court \u2014 the awe of the crown returned."),
    ("Blood and iron: ", "cleared the Mewati bandits around Delhi, crushed the doab rebels, pacified Katehar \u2014 roads became safe again."),
    ("Broke the Forty: ", "his own old comrades \u2014 sidelined, poisoned or executed; spies (barids) in every province and noble household."),
    ("Bengal rebellion (1279): ", "marched there at nearly eighty and made an example so terrifying Bengal stayed quiet for a generation."),
    ("The price of the frontier: ", "his beloved heir Prince Muhammad fell to the Mongols (1285); Balban's health broke, and he died in 1287."),
], Inches(0.8), Inches(1.55), SW - Inches(1.7), Inches(5.5), size=18, gap=12)

# ============================================================ 12. FALL
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "FALL OF THE DYNASTY (1287\u20131290)")
bullets(s, [
    ("Dynasties rarely survive their strongmen. ", "The nobles ignored Balban's chosen heir and crowned his teenage grandson Kaiqubad."),
    ("Three wasted years: ", "raised under suffocating discipline, Kaiqubad threw himself into pleasure \u2014 administration and health both collapsed."),
    ("Rise of the Khaljis: ", "the old Turkish party lost ground to the veteran commander Jalal-ud-din Khalji and his clan."),
    ("1290 \u2013 the Khalji Revolution: ", "the paralysed Kaiqubad was killed in his palace at Kilokhri; Jalal-ud-din took the throne."),
    ("More than a change of family: ", "it broke the Turkish slave elite's monopoly on power forever \u2014 the dynasty of former slaves fell to the very principle that had raised it: power belongs to the capable."),
], Inches(0.8), Inches(1.6), SW - Inches(1.7), Inches(5.3), size=19, gap=15)

# ============================================================ 13. ADMINISTRATION
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "ADMINISTRATION")
bullets(s, [
    ("The Sultan: ", "absolute in theory \u2014 military power + Islamic legitimacy + (after Balban) a semi-divine aura. In practice, he had to manage the nobles."),
    ("Great ministries: ", "diwan-i-wizarat (finance, under the wazir), ariz-i-mamalik (army), diwan-i-insha (correspondence), qazi (justice)."),
    ("The iqta system: ", "officers (muqtis) got the land revenue of a territory instead of salary \u2014 they kept troops, kept order, sent the surplus to Delhi."),
    ("Transferable, not hereditary: ", "strong sultans shuffled muqtis regularly so no officer could grow local roots \u2014 ingenious for a cash-poor state."),
    ("Army and intelligence: ", "heavy cavalry and war elephants; Balban paid the central army directly and planted barid informers everywhere."),
    ("Everyday India carried on: ", "village life, caste society and customary law continued \u2014 the state taxed the land but rarely touched daily life."),
], Inches(0.8), Inches(1.55), SW - Inches(1.7), Inches(5.5), size=18, gap=12)

# ============================================================ 14. ARCHITECTURE (images)
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "ART AND ARCHITECTURE")
img_w = Inches(3.1)
pic_fit(s, f"{ASSETS}/qutb_minar.jpg", SW - Inches(3.55), Inches(1.45), img_w, Inches(4.1))
pic_fit(s, f"{ASSETS}/quwwat.jpg", SW - Inches(6.85), Inches(1.45), img_w, Inches(4.1))
cap = box(s, SW - Inches(6.85), Inches(5.6), Inches(6.4), Inches(0.5))
p = cap.text_frame.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
set_run(p.add_run(), "Quwwat-ul-Islam mosque corridor  \u2022  Qutb Minar (72.5 m \u2014 world's tallest brick minaret)", 12, BODY_FONT, GRAY, italic=True)
bullets(s, [
    ("Quwwat-ul-Islam mosque: ", "Delhi's first great mosque \u2014 built on carved temple pillars; two artistic worlds colliding and merging."),
    ("Qutb Minar: ", "begun by Aibak, completed by Iltutmish \u2014 red sandstone, Quranic calligraphy."),
    ("Tombs: ", "Iltutmish's carved tomb and Sultan Ghari \u2014 the earliest Islamic tomb in India."),
    ("Balban's tomb: ", "ruined but historic \u2014 one of India's first true arches, pointing toward the Mughal domes to come."),
], Inches(0.75), Inches(1.5), Inches(5.6), Inches(5.2), size=16, gap=12)

# ============================================================ 15. LEGACY
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "LEGACY AND SIGNIFICANCE")
bullets(s, [
    ("Political: ", "made Delhi the imperial centre of India \u2014 a status it has never really lost \u2014 and created the model of sultan every later dynasty copied."),
    ("Administrative: ", "iqta, ministries, barid network, standing army \u2014 the scaffolding on which Khaljis, Tughlaqs and even Mughals built."),
    ("Economic: ", "the tanka\u2013jital currency anchored north Indian commerce for generations."),
    ("Strategic: ", "its defence of the north-west kept the Mongol catastrophe out of India \u2014 Indian cities were never burned like Merv or Baghdad."),
    ("Cultural: ", "Amir Khusrau's poetry, the Chishti saints (Bakhtiyar Kaki, Baba Farid), and the start of the Indo-Islamic synthesis in art and language."),
    ("A radical idea: ", "a slave could become sultan; a woman could rule an empire \u2014 the throne of Delhi could be earned, not just inherited."),
], Inches(0.8), Inches(1.55), SW - Inches(1.7), Inches(5.5), size=18, gap=12)

# ============================================================ 16. CONCLUSION
s = add_slide(); n += 1; side_bar(s); footer(s, n, TOTAL)
heading(s, "CONCLUSION")
bullets(s, [
    ("An empire founded by men who had once been merchandise ", "\u2014 the strangest and most instructive arc in medieval Indian history."),
    ("Aibak ", "turned a conqueror's garrisons into a kingdom; "),
    ("Iltutmish ", "gave it law, money, legitimacy \u2014 and saved it from Chingiz Khan with one brilliantly evasive letter."),
    ("Razia ", "showed how far ability could carry a person; her fate showed exactly where the limits lay."),
    ("Balban ", "rebuilt the majesty of the crown with equal parts ceremony and cruelty \u2014 and held the frontier at the cost of his son."),
    ("Eighty-four years ", "\u2014 less than one modern lifetime \u2014 yet in it an improvised military occupation became a settled state with a capital, a currency and a culture. The dynasties that followed built higher, but they built on this foundation."),
], Inches(0.8), Inches(1.5), SW - Inches(1.7), Inches(5.0), size=18, gap=12)
tb = box(s, Inches(0.8), SH - Inches(1.05), SW - Inches(1.7), Inches(0.7))
p = tb.text_frame.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
r = p.add_run(); set_run(r, "THANK YOU", 32, HEAD_FONT, BROWN); r.font.underline = True

OUT = "/home/user/SIH/assignment/Slave_Dynasty_Mamluk_Presentation.pptx"
prs.save(OUT)
print("saved", OUT, "| slides:", len(prs.slides.__iter__.__self__._sldIdLst))
