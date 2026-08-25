#!/usr/bin/env python3
"""
LegalEye core — extraction + validation engine for the
Legal Metrology (Packaged Commodities) Rules, 2011 (as amended).

Pipeline: OCR lines -> normalization -> targeted regex extraction per
declaration type -> rule checks R01..R12 -> weighted score & verdict.
"""
import re
import cv2
import numpy as np

# ----------------------------------------------------------------------------
# Package size classes -> minimum height of numerals/letters in net-qty
# declaration (Rule 14 r/w Seventh Schedule, PC Rules 2011)
# area of principal display panel:
SIZE_CLASSES = {
    "small":  {"label": "\u2264 200 cm\u00b2 (small pack)",   "min_mm": 1.0},
    "medium": {"label": "200\u2013500 cm\u00b2 (medium pack)", "min_mm": 2.0},
    "large":  {"label": "500\u20132500 cm\u00b2 (large pack)", "min_mm": 4.0},
    "xlarge": {"label": "> 2500 cm\u00b2 (bulk pack)",        "min_mm": 6.0},
}

MONTHS = "jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"
RE = {
    "mrp_key":   re.compile(r"(m\.?\s*r\.?\s?p\.?|maximum\s+retail\s+price)", re.I),
    "amount":    re.compile(r"(\d+(?:[.,]\d{1,2})?)"),
    "currency":  re.compile(r"(\u20b9|rs\.?|inr|/\u2212|/-)", re.I),
    "tax_line":  re.compile(r"inclusive\s*of\s*all\s*tax|incl\.?\s*of\s*all\s*tax", re.I),
    "net_qty":   re.compile(r"net\s*(qty|wt|weight|wgt|quantity|contents?|content)\s*[:\-.]?\s*"
                            r"(\d+(?:\.\d+)?)\s*(kgs?|kg|gms?|gm|g|mls?|ml|ltrs?|ltr|litres?|litre|l)(?-i:(?![a-z]))", re.I),
    "mfg_key":   re.compile(r"(mfd|mfg|pkd|p.k.d|packed\s*on|mfg\.?\s*date|mfg\.?\s*lic|manufactured)", re.I),
    "date_g":    re.compile(rf"\b({MONTHS})\w*\s*['.]?\s*(\d{{2,4}})\b|\b\d{{1,2}}\s*[/-]\s*\d{{4}}\b", re.I),
    "batch":     re.compile(r"\b(batch|b\.?\s*no|bn|lot)\s*(no|number)?\s*[:\-.]?\s*([A-Z0-9\-]{3,})\b", re.I),
    "fssai_key": re.compile(r"(fssai|f\.s\.s\.a\.i|lic\.?\s*no|license\s*no)", re.I),
    "digits13":  re.compile(r"\d{13,14}"),
    "email":     re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    "phone":     re.compile(r"(\+?91[\-\s]?[6-9]\d{9}\b|\b[6-9]\d{9}\b|1800[\-\s]?\d{3,4}[\-\s]?\d{3,4}|0\d{2,4}[\-\s]\d{6,8})"),
    "pincode":   re.compile(r"\b[1-8]\d{5}\b"),
    "packer":    re.compile(r"(mfdby|mfgby|pkdby|packedby|marketedby|mktdby|"
                            r"(mfd|mfg|pkd|packed|manufactur\w*|market\w*|mktd)[.\s]*(?:&\s*(and\s+)?|and\s+)?\s*by\b)", re.I),
    "care":      re.compile(r"(consumer\s*care|customer\s*care|consumer\s*support|helpline|toll\s*free)", re.I),
    "origin":    re.compile(r"(country\s*of\s*origin|product\s*of|made\s*in)\s*[:\-.]?\s*([A-Za-z ]+)", re.I),
    "importer":  re.compile(r"(imported\s*by|importer\s*[:\-]|imp\s*by)", re.I),
    "import_kw": re.compile(r"\b(imported|import)\b", re.I),
    "veg_word":  re.compile(r"\b(vegetarian|veg)\b", re.I),
    "food_kw":   re.compile(r"(biscuit|atta|wheat|flour|snack|bhujia|namkeen|chocol|wafer|cookie|edible|oil|ghee|"
                            r"spice|masala|food|food\s*park|juice|milk|dairy|bread|cake|nutrition|ingredient)", re.I),
}

FOOD_HINT = RE["food_kw"]


def _flat(s):
    return re.sub(r"\s+", "", s.lower())


def _bbox_of(line):
    pts = line["box"]
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    return [int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys))]


_RUPEE_CACHE = {}
def _rupee_template(h):
    """Render a ₹ glyph at height h and return its edge map (cached)."""
    if h in _RUPEE_CACHE:
        return _RUPEE_CACHE[h]
    from PIL import Image, ImageDraw, ImageFont
    img = Image.new("L", (h * 2, int(h * 1.6)), 0)
    d = ImageDraw.Draw(img)
    try:
        f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", h)
        d.text((2, 2), "\u20b9", font=f, fill=255)
    except Exception:
        return None
    arr = np.array(img)
    ys, xs = np.where(arr > 40)
    if len(ys) == 0:
        return None
    crop = arr[max(0, ys.min()-2):ys.max()+3, max(0, xs.min()-2):xs.max()+3]
    edge = cv2.Canny(crop, 60, 160)
    _RUPEE_CACHE[h] = edge
    return edge


def detect_rupee(img_bgr, line_box):
    """Detect the ₹ symbol inside/near the MRP line via edge-template matching.
    Returns (found: bool, box or None, best_score)."""
    H, W = img_bgr.shape[:2]
    x1, y1, x2, y2 = line_box
    pad = int((y2 - y1) * 0.9)
    x1e, x2e = max(0, x1 - pad), min(W, x2 + pad // 2)
    y1e, y2e = max(0, y1 - pad // 3), min(H, y2 + pad // 3)
    band = img_bgr[y1e:y2e, x1e:x2e]
    if band.size == 0:
        return False, None, 0.0
    gray = cv2.cvtColor(band, cv2.COLOR_BGR2GRAY)
    edge_full = cv2.Canny(gray, 60, 160)
    line_h = y2 - y1
    best, best_box = 0.0, None
    for gh in range(max(10, int(line_h * 0.55)), int(line_h * 1.15), 3):
        tpl = _rupee_template(gh)
        if tpl is None or tpl.shape[0] > edge_full.shape[0] or tpl.shape[1] > edge_full.shape[1]:
            continue
        m = cv2.matchTemplate(edge_full, tpl, cv2.TM_CCOEFF_NORMED)
        _, mx, _, loc = cv2.minMaxLoc(m)
        if mx > best:
            best = mx
            bx, by = loc[0] + x1e, loc[1] + y1e
            best_box = [bx, by, bx + tpl.shape[1], by + tpl.shape[0]]
    return best >= 0.45, best_box, round(float(best), 2)


def detect_veg_logo(img_bgr):
    """Detect the green dot-in-square veg mark (or brown non-veg triangle) via color masks."""
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    h, w = img_bgr.shape[:2]
    mask = cv2.inRange(hsv, np.array([35, 90, 50]), np.array([95, 255, 200]))
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    blobs = []
    for c in cnts:
        x, y, cw, ch = cv2.boundingRect(c)
        area = cv2.contourArea(c)
        if area < 25:
            continue
        blobs.append([x, y, x + cw, y + ch])
    # veg logo = a small cluster of green blobs (square border + filled dot)
    green_px = int(np.count_nonzero(mask))
    found = green_px > 40 and len(blobs) >= 1
    box = None
    if found and blobs:
        x1 = min(b[0] for b in blobs); y1 = min(b[1] for b in blobs)
        x2 = max(b[2] for b in blobs); y2 = max(b[3] for b in blobs)
        if (x2 - x1) < w * 0.25 and (y2 - y1) < h * 0.25:  # localized small mark
            box = [x1, y1, x2, y2]
    return found, box, green_px


def analyze(img_bgr, ocr_lines, *, package_class="small", label_width_mm=180.0,
            product_name=""):
    """Return full compliance result. ocr_lines: [{'box':[[x,y]x4],'text':str,'conf':float}]"""
    H, W = img_bgr.shape[:2]
    for ln in ocr_lines:
        ln["bbox"] = _bbox_of(ln)
        ln["flat"] = _flat(ln["text"])

    full_flat = "".join(ln["flat"] for ln in ocr_lines)
    lines = ocr_lines
    joined2 = [lines[i]["text"] + " " + (lines[i + 1]["text"] if i + 1 < len(lines) else "")
               for i in range(len(lines))]

    def find_lines(rx, hay=None, group=None):
        out = []
        for i, ln in enumerate(lines):
            src = (hay[i] if hay else ln["text"])
            if rx.search(src):
                out.append(i)
        return out

    def ctx_box(idxs, span=2):
        sel = []
        for i in idxs:
            for j in range(i, min(i + span, len(lines))):
                sel.append(lines[j]["bbox"])
        if not sel:
            return None
        return [min(b[0] for b in sel), min(b[1] for b in sel),
                max(b[2] for b in sel), max(b[3] for b in sel)]

    checks = []
    extracted = {}

    def add(cid, title, rule, status, detail, evidence="", box=None,
            weight=10, fix=""):
        checks.append(dict(id=cid, title=title, rule_ref=rule, status=status,
                           detail=detail, evidence=evidence, box=box,
                           weight=weight, fix=fix))

    # ---------------- R01 manufacturer/packer name & address ----------------
    pi = find_lines(RE["packer"])
    pin_ok = any(RE["pincode"].search(s) for s in (joined2[i] for i in pi)) if pi else False
    name_ok = bool(pi)
    if name_ok and pin_ok:
        add("R01", "Name & address of Manufacturer/Packer", "Rule 6(1)(a)", "pass",
            "Manufacturer/packer name with full address (incl. PIN) declared.",
            evidence=lines[pi[0]]["text"], box=ctx_box(pi), weight=14,
            fix="")
    elif name_ok:
        add("R01", "Name & address of Manufacturer/Packer", "Rule 6(1)(a)", "fail",
            "Packer name found but complete postal address with PIN code is missing.",
            evidence=lines[pi[0]]["text"], box=ctx_box(pi), weight=14,
            fix="Print full postal address with PIN code.")
    else:
        add("R01", "Name & address of Manufacturer/Packer", "Rule 6(1)(a)", "fail",
            "No manufacturer / packer name and address declaration detected.",
            evidence="", box=None, weight=14,
            fix="Declare 'Mfd. by / Pkd. by / Marketed by' with full address & PIN.")

    # ---------------- R02 common name of commodity ----------------
    name_lines = [i for i, ln in enumerate(lines) if ln["bbox"][1] < H * 0.42]
    common = bool(name_lines)
    add("R02", "Common/generic name of the commodity", "Rule 6(1)(b)",
        "pass" if common or product_name else "fail",
        f"Commodity name declared{f' ({product_name})' if product_name else ''}." if (common or product_name)
        else "Commodity generic name not detected on principal display panel.",
        evidence=(lines[name_lines[0]]["text"] if common else product_name),
        box=ctx_box(name_lines[:1]) if common else None, weight=8,
        fix="" if common else "Show the generic name of the commodity prominently.")

    # ---------------- R03 net quantity declaration ----------------
    nq_hit = None
    for i, ln in enumerate(lines):
        m = RE["net_qty"].search(ln["text"])
        if m:
            nq_hit = (i, m)
            break
    if nq_hit:
        i, m = nq_hit
        extracted["net_qty"] = {"text": m.group(0), "value": float(m.group(2)), "unit": m.group(3),
                                "line_box": lines[i]["bbox"]}
        add("R03", "Net quantity in standard units", "Rule 6(1)(c) r/w Rule 7", "pass",
            f"Net quantity declared: {m.group(2)} {m.group(3)}.", evidence=lines[i]["text"],
            box=lines[i]["bbox"], weight=14)
    else:
        add("R03", "Net quantity in standard units", "Rule 6(1)(c) r/w Rule 7", "fail",
            "Net quantity declaration not detected in standard units (g/kg/ml/L).",
            weight=14, fix="Declare 'Net Qty: ___ g/ml' in standard metric units.")

    # ---------------- R04 net-qty font height ----------------
    cls = SIZE_CLASSES.get(package_class, SIZE_CLASSES["small"])
    if nq_hit:
        i, m = nq_hit
        box_h = lines[i]["bbox"][3] - lines[i]["bbox"][1]
        GLYPH_FACTOR = 0.62  # OCR line-box is taller than the actual glyphs
        mm = box_h * GLYPH_FACTOR * (label_width_mm / W)
        req = cls["min_mm"]
        ok = mm >= req * 0.85
        extracted["net_qty"].update({"measured_mm": round(mm, 2), "required_mm": req})
        add("R04", "Minimum height of numerals in net-qty", "Rule 14 r/w Seventh Schedule",
            "pass" if ok else "fail",
            f"Measured \u2248 {mm:.1f} mm vs minimum {req:.0f} mm for panel {cls['label']}"
            + (" (within tolerance)." if ok else f" \u2014 short by {req-mm:.1f} mm."),
            evidence=lines[i]["text"], box=lines[i]["bbox"], weight=10,
            fix="" if ok else f"Increase numeral height to \u2265 {req} mm for panel class {cls['label']}.")
    else:
        add("R04", "Minimum height of numerals in net-qty", "Rule 14 r/w Seventh Schedule", "fail",
            "Cannot verify character height \u2014 net quantity not found.", weight=10,
            fix="Declare net quantity with numerals of prescribed minimum height.")

    # ---------------- R05 MRP declaration ----------------
    mrp_i, mrp_m, cur_ok = None, None, False
    for i, ln in enumerate(lines):
        if RE["mrp_key"].search(ln["text"]):
            am = RE["amount"].search(ln["text"], RE["mrp_key"].search(ln["text"]).end())
            if am:
                mrp_i, mrp_m = i, am
                cur_ok = bool(RE["currency"].search(ln["text"]))
                break
    if mrp_i is not None:
        # robust ₹ detection: OCR text (may keep ₹) + visual edge-template match
        r_found, r_box, r_score = detect_rupee(img_bgr, lines[mrp_i]["bbox"])
        cur_ok = cur_ok or r_found
        extracted["mrp"] = {"value": mrp_m.group(1), "currency": cur_ok,
                            "symbol_conf": r_score, "line_box": lines[mrp_i]["bbox"],
                            "symbol_box": r_box}
        if cur_ok:
            add("R05", "Maximum Retail Price (MRP) in \u20b9", "Rule 6(1)(f) r/w Rule 18", "pass",
                f"MRP declared: \u20b9 {mrp_m.group(1)} (currency symbol present).",
                evidence=lines[mrp_i]["text"], box=lines[mrp_i]["bbox"], weight=14)
        else:
            add("R05", "Maximum Retail Price (MRP) in \u20b9", "Rule 6(1)(f) r/w Rule 18(2)", "fail",
                f"Price '{mrp_m.group(1)}' shown WITHOUT \u20b9/Rs. currency notation.",
                evidence=lines[mrp_i]["text"], box=lines[mrp_i]["bbox"], weight=14,
                fix="Prefix price with \u20b9 or 'Rs.' as legally required.")
    else:
        add("R05", "Maximum Retail Price (MRP) in \u20b9", "Rule 6(1)(f) r/w Rule 18", "fail",
            "No MRP declaration found \u2014 sale without MRP is a penal offence.", weight=14,
            fix="Declare 'M.R.P. \u20b9 ___' on the package.")

    # ---------------- R06 'inclusive of all taxes' ----------------
    tax_idx = find_lines(RE["tax_line"])
    tax_flat = bool(re.search(r"inclusiveofalltax|inclofalltax|inclusivofalltax", full_flat))
    if tax_idx or tax_flat:
        add("R06", "'Inclusive of all taxes' marking", "Rule 6(1)(f) (2017 amdt.)", "pass",
            "MRP qualified as inclusive of all taxes.", evidence=(lines[tax_idx[0]]["text"] if tax_idx else ""),
            box=ctx_box(tax_idx) if tax_idx else (lines[mrp_i]["bbox"] if mrp_i is not None else None), weight=8)
    else:
        add("R06", "'Inclusive of all taxes' marking", "Rule 6(1)(f) (2017 amdt.)", "fail",
            "'Inclusive of all taxes' endorsement missing next to MRP.",
            evidence="", box=lines[mrp_i]["bbox"] if mrp_i is not None else None, weight=8,
            fix="Add '(Inclusive of all taxes)' with the MRP.")

    # ---------------- R07 month & year of manufacture/packing ----------------
    mfg_i = find_lines(RE["mfg_key"])
    mfg_ok, mfg_ev, mfg_box = False, "", None
    for i in mfg_i:
        seg = lines[i]["text"] + " " + (lines[i+1]["text"] if i+1 < len(lines) else "")
        if re.search(rf"({MONTHS})", seg, re.I) and re.search(r"(19|20)\d{2}", seg):
            mfg_ok, mfg_ev, mfg_box = True, lines[i]["text"], ctx_box([i]); break
        if re.search(r"\b\d{1,2}\s*[/-]\s*(19|20)?\d{2}\b", seg):
            mfg_ok, mfg_ev, mfg_box = True, lines[i]["text"], ctx_box([i]); break
    if mfg_ok:
        extracted["mfg"] = mfg_ev
        add("R07", "Month & year of manufacture / packing", "Rule 6(1)(d)", "pass",
            "Month-year of manufacture/packing declared.", evidence=mfg_ev, box=mfg_box, weight=12)
    else:
        add("R07", "Month & year of manufacture / packing", "Rule 6(1)(d)", "fail",
            "Month & year of manufacture/import/packing not found.",
            weight=12, fix="Print 'MFD/PKD: MM/YYYY' legibly.")

    # ---------------- R08 consumer care details ----------------
    ci = find_lines(RE["care"])
    care_seg = ""
    if ci:
        care_seg = " ".join(lines[j]["text"] for j in range(ci[0], min(ci[0] + 3, len(lines))))
    ph = bool(RE["phone"].search(care_seg))
    em = bool(RE["email"].search(care_seg))
    ad = bool(RE["pincode"].search(care_seg)) or (len(care_seg) > 60 and "," in care_seg)
    comp = sum([ph, em, ad])
    if ci and comp >= 2:
        add("R08", "Consumer care (name/address, phone, email)", "Rule 6(1)(g)", "pass",
            f"Consumer care provided ({'/'.join(x for x, ok in zip(['phone', 'email', 'address'], [ph, em, ad]) if ok)}).",
            evidence=lines[ci[0]]["text"], box=ctx_box(ci, 3), weight=12)
    elif ci:
        add("R08", "Consumer care (name/address, phone, email)", "Rule 6(1)(g)", "fail",
            f"Consumer care incomplete \u2014 found only {comp}/3 of phone, email, address.",
            evidence=lines[ci[0]]["text"], box=ctx_box(ci, 3), weight=12,
            fix="Add consumer-care name/address + phone + e-mail.")
    else:
        add("R08", "Consumer care (name/address, phone, email)", "Rule 6(1)(g)", "fail",
            "No consumer care cell details declared.", weight=12,
            fix="Declare consumer care name/address, phone no. & e-mail.")

    # ---------------- R09 import declarations ----------------
    imported = ("import" in full_flat) or bool(
        RE["origin"].search(" ".join(ln["text"] for ln in lines)))
    if imported:
        oi = find_lines(RE["origin"]); ii = find_lines(RE["importer"])
        ok_o, ok_i = bool(oi), bool(ii)
        if ok_o and ok_i:
            add("R09", "Country of origin + importer for imports", "Rule 6(1)(c),(e) (2017 amdt.)", "pass",
                "Country of origin and importer details declared.",
                evidence=lines[oi[0]]["text"], box=ctx_box(oi + ii), weight=12)
        else:
            miss = []
            if not ok_o: miss.append("country of origin")
            if not ok_i: miss.append("name & address of importer")
            add("R09", "Country of origin + importer for imports", "Rule 6(1)(c),(e) (2017 amdt.)", "fail",
                "Imported product missing: " + " and ".join(miss) + ".",
                evidence="", box=None, weight=12,
                fix=f"Declare {' and '.join(miss)}.")
    else:
        add("R09", "Country of origin + importer for imports", "Rule 6(1)(c),(e) (2017 amdt.)", "na",
            "Not an imported product \u2014 rule not applicable.", weight=0)

    # ---------------- R10 batch / lot number ----------------
    bi = find_lines(RE["batch"])
    if bi:
        add("R10", "Batch / lot number", "Best practice (Rule 6 prov.), r/w FSSAI", "pass",
            "Batch/lot marking detected.", evidence=lines[bi[0]]["text"], box=ctx_box(bi), weight=6)
    else:
        add("R10", "Batch / lot number", "Best practice (Rule 6 prov.), r/w FSSAI", "fail",
            "Batch/lot number not detected (required for traceability/recalls).", weight=6,
            fix="Print batch/lot number.")

    # ---------------- R11 FSSAI licence (food products) ----------------
    is_food = bool(FOOD_HINT.search(" ".join(ln["text"] for ln in lines)))
    if is_food:
        f_ok, f_ev, f_box = False, "", None
        digits13 = re.compile(r"\d{13,15}")
        for i, ln in enumerate(lines):
            if RE["fssai_key"].search(ln["text"]):
                seg = ln["text"] + " " + (lines[i + 1]["text"] if i + 1 < len(lines) else "")
                d_only = re.sub(r"\D", "", seg)
                if digits13.search(d_only):
                    f_ok, f_ev, f_box = True, ln["text"], ctx_box([i], 2); break
        if not f_ok:  # any standalone long digit run
            for i, ln in enumerate(lines):
                if digits13.search(re.sub(r"\D", "", ln["text"])):
                    f_ok, f_ev, f_box = True, ln["text"], ctx_box([i]); break
        add("R11", "FSSAI licence number (food)", "FSS Act 2006 r/w PC Rules", "pass" if f_ok else "fail",
            "FSSAI licence number declared." if f_ok else "Food package without a 14-digit FSSAI licence number.",
            evidence=f_ev, box=f_box, weight=6,
            fix="" if f_ok else "Print 14-digit FSSAI licence number.")
    else:
        add("R11", "FSSAI licence number (food)", "FSS Act 2006 r/w PC Rules", "na",
            "Not a food product \u2014 not applicable.", weight=0)

    # ---------------- R12 veg / non-veg logo (food) ----------------
    if is_food:
        logo_found, logo_box, gpx = detect_veg_logo(img_bgr)
        vi = find_lines(RE["veg_word"])
        ok = logo_found or bool(vi)
        add("R12", "Vegetarian / non-vegetarian symbol", "FSSAI FOPR 2006, Reg. 2.2.2(4)",
            "pass" if ok else "fail",
            ("Veg symbol detected (green mark" + (" + text" if vi else "") + ").") if ok
            else "Mandatory green/brown veg-nonveg symbol not found on food pack.",
            evidence=(lines[vi[0]]["text"] if vi else ""), box=logo_box or ctx_box(vi), weight=6,
            fix="" if ok else "Affix the prescribed veg/non-veg logo.")
    else:
        add("R12", "Vegetarian / non-vegetarian symbol", "FSSAI FOPR 2006", "na",
            "Not a food product \u2014 not applicable.", weight=0)

    # ---------------- score & verdict ----------------
    tot = sum(c["weight"] for c in checks if c["status"] != "na")
    got = sum(c["weight"] for c in checks if c["status"] == "pass")
    score = round(100 * got / tot) if tot else 0
    fails = [c for c in checks if c["status"] == "fail"]
    critical_fail = any(c["id"] in ("R03", "R05") for c in fails)  # can't legally be sold
    if score >= 85 and not critical_fail:
        verdict, grade = "COMPLIANT", "A"
    elif score >= 60 and not critical_fail:
        verdict, grade = "NON-COMPLIANT (minor)", "B"
    else:
        verdict, grade = "NON-COMPLIANT (major violations)", "C"

    return {
        "verdict": verdict, "grade": grade, "score": score,
        "passed": got, "failed_checks": len(fails), "n_checks": sum(1 for c in checks if c["status"] != "na"),
        "checks": checks, "extracted": extracted,
        "meta": {"package_class": package_class, "label_width_mm": label_width_mm,
                 "imported": imported, "is_food": is_food,
                 "img_w": W, "img_h": H},
        "ocr_lines": [{"text": l["text"], "bbox": l["bbox"], "conf": round(float(l["conf"]), 2)} for l in lines],
    }
