#!/usr/bin/env python3
"""Generate realistic packaged-commodity labels (compliant + violating) for the demo.
Each label is drawn with PIL so text is OCR-perfect and violations are controlled.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static", "samples")
os.makedirs(OUT, exist_ok=True)

FD = "/usr/share/fonts/truetype/dejavu"
def font(name, size):
    return ImageFont.truetype(f"{FD}/{name}", size)

F = {
    "brand":  lambda s: font("DejaVuSans-Bold.ttf", s),
    "sans":   lambda s: font("DejaVuSans.ttf", s),
    "mono":   lambda s: font("DejaVuSansMono.ttf", s),
}

def texture(img, strength=6):
    """subtle paper noise"""
    px = img.load()
    w, h = img.size
    rnd = random.Random(7)
    for _ in range(w*h//40):
        x, y = rnd.randrange(w), rnd.randrange(h)
        r, g, b = px[x, y][:3]
        d = rnd.randint(-strength, strength)
        px[x, y] = (max(0, min(255, r+d)), max(0, min(255, g+d)), max(0, min(255, b+d)))
    return img

def barcode(d, x, y, w, h, seed=42):
    rnd = random.Random(seed)
    cx = x
    while cx < x + w:
        bw = rnd.choice([1, 1, 2, 2, 3])
        if rnd.random() < 0.55:
            d.rectangle([cx, y, cx+bw, y+h], fill=(20, 20, 20))
        cx += bw + rnd.choice([1, 2])
    return (x, y, x+w, y+h)

def veg_logo(d, x, y, s=22, veg=True):
    d.rectangle([x, y, x+s, y+s], outline=(0, 120, 40) if veg else (120, 30, 20), width=3)
    cx, cy = x+s//2, y+s//2
    col = (0, 150, 40) if veg else (150, 30, 20)
    if veg:
        d.ellipse([cx-7, cy-7, cx+7, cy+7], fill=col)
    else:
        d.polygon([(cx, cy-8), (cx+8, cy+6), (cx-8, cy+6)], fill=col)

def fssai_badge(d, x, y, lic, w=210):
    d.rectangle([x, y, x+w, y+34], fill=(245, 245, 245), outline=(140, 140, 140))
    d.ellipse([x+6, y+7, x+26, y+27], fill=(30, 90, 170))
    d.text((x+34, y+8), f"FSSAI Lic. No. {lic}", font=F["mono"](15), fill=(40, 40, 40))

def header_band(d, w, h1, c1, c2, steps=70):
    for i in range(steps):
        yy = h1 * i // steps
        c = tuple(int(c1[k] + (c2[k]-c1[k]) * i/steps) for k in range(3))
        d.rectangle([0, yy, w, yy + h1//steps + 2], fill=c)

# ----------------------------------------------------------------------------------
def label_biscuits():
    """KrunchKrust Bourbon — FULLY COMPLIANT. Expect PASS."""
    W, H = 860, 560
    img = Image.new("RGB", (W, H), (250, 246, 238))
    d = ImageDraw.Draw(img)
    header_band(d, W, 150, (94, 22, 24), (150, 44, 36))
    d.text((W//2-290, 22), "KRUNCHKRUST", font=F["brand"](64), fill=(255, 224, 130))
    d.text((W//2-160, 100), "BOURBON CREAM BISCUITS", font=F["brand"](26), fill=(255, 255, 255))
    d.ellipse([W-150, 55, W-95, 110], fill=(115, 60, 20), outline=(255, 224, 130), width=3)
    d.ellipse([W-140, 65, W-105, 100], fill=(70, 35, 10))
    veg_logo(d, 28, 170, 26)
    d.text((62, 172), "Vegetarian Product", font=F["sans"](16), fill=(60, 60, 60))
    d.text((28, 210), "Ingredients: Wheat flour, Sugar, Edible vegetable oil, Cocoa solids (4.5%),", font=F["sans"](15), fill=(80, 80, 80))
    d.text((28, 230), "Leavening agents (500(ii)), Salt, Emulsifier (322), Artificial vanilla flavour.", font=F["sans"](15), fill=(80, 80, 80))
    fssai_badge(d, 28, 262, "10012043002567")
    # big declarations
    d.rectangle([28, 310, 420, 352], outline=(30, 30, 30), width=2)
    d.text((40, 316), "Net Qty: 250 g", font=F["brand"](28), fill=(20, 20, 20))
    d.rectangle([440, 306, 668, 356], fill=(255, 255, 255), outline=(20, 20, 20), width=2)
    d.text((452, 312), "M.R.P. \u20b9 120.00", font=F["brand"](26), fill=(160, 20, 20))
    d.text((676, 322), "(Inclusive of all taxes)", font=F["sans"](15), fill=(60, 60, 60))
    d.text((28, 372), "MFD: JAN 2026   |   Best Before: 6 Months from Packing", font=F["sans"](18), fill=(40, 40, 40))
    d.text((28, 398), "Batch No: KK26A104", font=F["sans"](16), fill=(70, 70, 70))
    d.text((28, 428), "Mfd. & Marketed by: KrunchKrust Foods Pvt. Ltd.,", font=F["sans"](17), fill=(30, 30, 30))
    d.text((28, 450), "Plot 14, MIDC Industrial Area, Nashik, Maharashtra - 422010, India", font=F["sans"](17), fill=(30, 30, 30))
    d.text((28, 478), "Consumer Care: care@krunchkrust.in | 1800-266-1101", font=F["sans"](17), fill=(30, 30, 30))
    d.text((28, 502), "(www.krunchkrust.in)", font=F["sans"](15), fill=(90, 90, 90))
    barcode(d, 640, 430, 180, 64, seed=11)
    texture(img)
    img.save(f"{OUT}/biscuits_compliant.png")

# ----------------------------------------------------------------------------------
def label_shampoo():
    """Herbal shampoo — violations: MRP without currency & without 'inclusive of all taxes',
    consumer care missing email+phone, no batch no. Expect MAJOR."""
    W, H = 700, 620
    img = Image.new("RGB", (W, H), (238, 250, 240))
    d = ImageDraw.Draw(img)
    header_band(d, W, 120, (16, 92, 50), (40, 140, 80))
    d.text((W//2-210, 18), "VERDANT HERBALS", font=F["brand"](46), fill=(230, 255, 230))
    d.text((W//2-170, 76), "Anti-Hairfall Shampoo", font=F["sans"](28), fill=(255, 255, 255))
    d.polygon([(W//2-30, 130), (W//2+30, 130), (W//2, 180)], fill=(30, 110, 60))
    d.text((30, 200), "With Bhringraj, Amla & Neem extracts", font=F["sans"](18), fill=(50, 90, 60))
    d.text((30, 232), "For strong, healthy hair. Paraben free.", font=F["sans"](16), fill=(70, 110, 80))
    d.rectangle([30, 270, 300, 316], outline=(20, 20, 20), width=2)
    d.text((42, 276), "Net Contents: 200 ml", font=F["brand"](24), fill=(20, 20, 20))
    # VIOLATION 1: bare number, no Rs symbol
    d.text((330, 274), "M.R.P. 210", font=F["brand"](28), fill=(20, 20, 20))
    # VIOLATION 2: no 'inclusive of all taxes' line anywhere
    d.text((30, 336), "Mfg. Date: 12/2025", font=F["sans"](18), fill=(40, 40, 40))
    d.text((30, 368), "Marketed by: Verdant Herbals, Haridwar, Uttarakhand - 249403", font=F["sans"](17), fill=(30, 30, 30))
    # VIOLATION 3: consumer care block ONLY has address (no phone, no email)
    d.text((30, 396), "Consumer Care: Verdant Herbals, SIDCUL, Haridwar - 249403", font=F["sans"](17), fill=(30, 30, 30))
    barcode(d, 470, 400, 180, 60, seed=22)
    d.text((30, 470), "Storage: Store in cool and dry place. For external use only.", font=F["sans"](14), fill=(90, 90, 90))
    d.text((30, 500), "Contains: Aqua, SLES, Cocamidopropyl betaine, Herbal extracts 2.2%,", font=F["sans"](13), fill=(90, 90, 90))
    d.text((30, 520), "Fragrance, Preservatives, Colour.", font=F["sans"](13), fill=(90, 90, 90))
    texture(img)
    img.save(f"{OUT}/shampoo_violations.png")

# ----------------------------------------------------------------------------------
def label_atta():
    """Whole wheat atta 5kg — violations: no month-year of packing, net-qty font too small,
    MRP missing inclusive line. Expect MAJOR."""
    W, H = 900, 560
    img = Image.new("RGB", (W, H), (250, 243, 226))
    d = ImageDraw.Draw(img)
    header_band(d, W, 130, (150, 90, 12), (200, 140, 30))
    d.text((W//2-260, 24), "GOLDENHARVEST", font=F["brand"](58), fill=(255, 250, 220))
    d.text((W//2-180, 94), "100% Whole Wheat Atta", font=F["sans"](26), fill=(255, 255, 255))
    for i in range(5):  # wheat ears
        x = 60 + i*20
        d.ellipse([x, 60, x+10, 78], fill=(235, 190, 90))
        d.line([x+5, 78, x+5, 96], fill=(235, 190, 90), width=2)
    veg_logo(d, 30, 162, 24)
    d.text((62, 164), "Vegetarian", font=F["sans"](15), fill=(70, 70, 70))
    # net qty in TINY font (violation vs required 4mm for 500-2500 cm2 class)
    d.text((30, 202), "Net Wt: 5 kg", font=F["sans"](11), fill=(40, 40, 40))
    d.text((30, 236), "M.R.P. \u20b9 285.00", font=F["brand"](26), fill=(20, 20, 20))
    d.text((30, 272), "Best before 3 months from date of packing", font=F["sans"](16), fill=(50, 50, 50))
    # VIOLATION: no MFD/PKD month-year anywhere
    d.text((30, 300), "Batch: GH-L7741", font=F["sans"](15), fill=(70, 70, 70))
    fssai_badge(d, 30, 330, "21214988001234")
    d.text((30, 378), "Pkd. by: GoldenHarvest Flour Mills, Village Rasulpur, District Karnal,", font=F["sans"](17), fill=(30, 30, 30))
    d.text((30, 400), "Haryana - 132001", font=F["sans"](17), fill=(30, 30, 30))
    d.text((30, 428), "Customer Care: support@goldenharvest.in | 0124-4662211", font=F["sans"](17), fill=(30, 30, 30))
    barcode(d, 620, 420, 190, 66, seed=33)
    texture(img)
    img.save(f"{OUT}/atta_violations.png")

# ----------------------------------------------------------------------------------
def label_choco():
    """Imported wafers — violations: no country of origin, no importer name/address.
    Expect MAJOR (import rules)."""
    W, H = 780, 520
    img = Image.new("RGB", (W, H), (46, 30, 66))
    d = ImageDraw.Draw(img)
    header_band(d, W, 120, (88, 40, 120), (140, 80, 180))
    d.text((W//2-230, 20), "CHOCOROYAL", font=F["brand"](56), fill=(255, 215, 0))
    d.text((W//2-150, 86), "IMPORTED WAFER ROLLS", font=F["sans"](24), fill=(245, 235, 255))
    d.text((30, 150), "Premium hazelnut cocoa wafers. Imported for the discerning palate.", font=F["sans"](17), fill=(220, 210, 235))
    d.rectangle([30, 196, 330, 240], outline=(255, 215, 0), width=2)
    d.text((42, 202), "Net Qty: 150 g", font=F["brand"](24), fill=(255, 255, 255))
    d.text((360, 198), "M.R.P. \u20b9 350.00", font=F["brand"](26), fill=(255, 224, 130))
    d.text((360, 232), "(Inclusive of all taxes)", font=F["sans"](14), fill=(220, 210, 235))
    d.text((30, 260), "MFD: 02/2026   |   Expiry: 10/2026", font=F["sans"](17), fill=(235, 225, 245))
    d.text((30, 288), "Batch No: CR-IMP-9931", font=F["sans"](16), fill=(235, 225, 245))
    fssai_badge(d, 30, 320, "11523998000345")
    # VIOLATION: marketed-by only a trading co. with no address / no 'Imported by' / no origin
    d.text((30, 368), "Marketed by: Royal Trading Company", font=F["sans"](17), fill=(200, 190, 220))
    d.text((30, 396), "Consumer Care: help@chocoroyal.in | 1800-121-9988", font=F["sans"](17), fill=(200, 190, 220))
    veg_logo(d, 30, 430, 24)
    barcode(d, 560, 420, 170, 60, seed=44)
    d.text((30, 470), "Store in cool dry place away from sunlight.", font=F["sans"](13), fill=(170, 160, 190))
    texture(img)
    img.save(f"{OUT}/choco_import_violations.png")

# ----------------------------------------------------------------------------------
def label_namkeen():
    """Aloo bhujia — SEVERE: MRP entirely missing + no veg logo. Expect MAJOR."""
    W, H = 820, 540
    img = Image.new("RGB", (W, H), (255, 240, 220))
    d = ImageDraw.Draw(img)
    header_band(d, W, 140, (170, 60, 10), (230, 110, 20))
    d.text((W//2-260, 24), "TADKA TREAT", font=F["brand"](62), fill=(255, 245, 210))
    d.text((W//2-190, 100), "Aloo Bhujia - Desi Style", font=F["sans"](26), fill=(255, 255, 255))
    d.text((30, 170), "Crispy potato strands with authentic spices", font=F["sans"](18), fill=(80, 50, 20))
    d.rectangle([30, 210, 320, 254], outline=(150, 60, 10), width=2)
    d.text((42, 216), "Net Wt: 400 g", font=F["brand"](24), fill=(120, 40, 5))
    # VIOLATION 1: NO MRP anywhere !
    d.text((30, 274), "MFD/PKD: 05/2026", font=F["sans"](17), fill=(50, 50, 50))
    d.text((30, 302), "Batch: TT-AB-5511", font=F["sans"](16), fill=(70, 70, 70))
    fssai_badge(d, 30, 332, "10923999000112")
    d.text((30, 376), "Mfd by: Tadka Treat Snacks, 21 Food Park, Indore, MP - 452010", font=F["sans"](17), fill=(30, 30, 30))
    d.text((30, 404), "Consumer Care: 1800-313-2024 | care@tadkatreat.in", font=F["sans"](17), fill=(30, 30, 30))
    # VIOLATION 2: no veg logo though food product
    d.text((30, 440), "Ingredients: Potato (62%), Edible vegetable oil, Chickpea flour, Spices & condiments, Salt.", font=F["sans"](14), fill=(90, 70, 50))
    barcode(d, 600, 430, 180, 62, seed=55)
    texture(img)
    img.save(f"{OUT}/namkeen_severe.png")

if __name__ == "__main__":
    label_biscuits(); label_shampoo(); label_atta(); label_choco(); label_namkeen()
    print("labels written to", OUT)
