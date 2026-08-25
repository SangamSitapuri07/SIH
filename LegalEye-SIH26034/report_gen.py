#!/usr/bin/env python3
"""Generate a PDF compliance report (Legal Metrology (PC) Rules, 2011)."""
import io, datetime
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.colors import HexColor, white
from reportlab.pdfgen import canvas

NAVY = HexColor("#0f2540"); SAFF = HexColor("#e8752a"); GREEN = HexColor("#157a3d")
RED = HexColor("#b3342a"); GREY = HexColor("#5c6b7a"); LINE = HexColor("#c7d2de")


def _status_color(status):
    return {"pass": GREEN, "fail": RED}.get(status, GREY)


def build_pdf(result, product_name, thumb_path=None):
    buf = io.BytesIO()
    W, H = A4
    c = canvas.Canvas(buf, pagesize=A4)

    # tricolor strip
    c.setFillColor(SAFF); c.rect(0, H-8, W, 8, stroke=0, fill=1)
    # header
    c.setFillColor(NAVY); c.rect(0, H-78, W, 70, stroke=0, fill=1)
    c.setFillColor(white); c.setFont("Helvetica-Bold", 20)
    c.drawString(40, H-40, "LegalEye \u2014 Packaged Commodity Compliance Report")
    c.setFont("Helvetica", 10); c.setFillColor(HexColor("#c9d6e4"))
    c.drawString(40, H-58, "As per the Legal Metrology (Packaged Commodities) Rules, 2011 read with the Legal Metrology Act, 2009")
    c.setFont("Helvetica-Bold", 10)
    c.drawRightString(W-40, H-40, f"Report ID: {result['scan_id']}")
    c.drawRightString(W-40, H-54, datetime.datetime.now().strftime("%d %b %Y, %H:%M IST"))

    y = H - 110
    # verdict banner
    vcolor = GREEN if result["grade"] == "A" else (SAFF if result["grade"] == "B" else RED)
    c.setFillColor(vcolor); c.roundRect(40, y-46, W-80, 46, 6, stroke=0, fill=1)
    c.setFillColor(white); c.setFont("Helvetica-Bold", 15)
    c.drawString(54, y-30, f"VERDICT: {result['verdict']}")
    c.setFont("Helvetica-Bold", 24)
    c.drawRightString(W-54, y-35, f"{result['score']}/100  (Grade {result['grade']})")
    y -= 74

    # product info
    c.setFillColor(NAVY); c.setFont("Helvetica-Bold", 12)
    c.drawString(40, y, "Inspected Consignment"); y -= 15
    c.setFont("Helvetica", 10); c.setFillColor(HexColor("#333333"))
    meta = result.get("meta", {})
    ex = result.get("extracted", {})
    info = [
        ("Product", product_name or "\u2014"),
        ("Net quantity", f"{ex['net_qty']['value']} {ex['net_qty']['unit']}" if ex.get("net_qty") else "not detected"),
        ("MRP", (("Rs. " if ex["mrp"].get("currency") else "") + str(ex["mrp"]["value"]) + ("" if ex["mrp"].get("currency") else "  (currency mark missing)")) if ex.get("mrp") else "NOT DECLARED"),
        ("Pack class (display panel)", f"{meta.get('package_class','\u2014')}  \u00b7  est. label width {meta.get('label_width_mm','\u2014')} mm"),
        ("Imported product", "Yes" if meta.get("imported") else "No"),
    ]
    for k, v in info:
        c.setFont("Helvetica-Bold", 9.5); c.drawString(40, y, k + ":")
        c.setFont("Helvetica", 9.5); c.drawString(200, y, str(v))
        y -= 13
    y -= 12

    # checks table
    c.setFillColor(NAVY); c.rect(40, y-14, W-80, 16, stroke=0, fill=1)
    c.setFillColor(white); c.setFont("Helvetica-Bold", 9)
    c.drawString(46, y-10, "#")
    c.drawString(70, y-10, "Declaration checked")
    c.drawString(300, y-10, "Rule reference")
    c.drawString(400, y-10, "Evidence on pack")
    c.drawRightString(W-46, y-10, "Status")
    y -= 18
    c.setFont("Helvetica", 8.6)
    for chk in result["checks"]:
        if chk["status"] == "na":
            continue
        row_h = 26
        if y < 90:
            c.showPage(); y = H - 60
        c.setStrokeColor(LINE); c.setLineWidth(0.5)
        c.line(40, y-row_h+6, W-40, y-row_h+6)
        c.setFont("Helvetica-Bold", 8.6); c.setFillColor(NAVY)
        c.drawString(46, y-8, chk["id"])
        c.setFont("Helvetica", 8.6); c.setFillColor(HexColor("#222222"))
        c.drawString(70, y-8, chk["title"][:44])
        c.setFillColor(GREY); c.setFont("Helvetica-Oblique", 8)
        c.drawString(70, y-18, chk["detail"][:86])
        c.setFont("Helvetica", 8); c.setFillColor(GREY)
        c.drawString(300, y-8, chk["rule_ref"][:30])
        ev = (chk.get("evidence") or "")[:34]
        c.drawString(400, y-8, ev)
        sc = _status_color(chk["status"])
        c.setFillColor(sc); c.setFont("Helvetica-Bold", 9)
        c.drawRightString(W-46, y-8, "PASS" if chk["status"] == "pass" else "FAIL")
        y -= row_h
    y -= 10

    # violations summary
    fails = [x for x in result["checks"] if x["status"] == "fail"]
    c.setFillColor(NAVY); c.setFont("Helvetica-Bold", 12)
    c.drawString(40, y, f"Violations Summary ({len(fails)})"); y -= 14
    if not fails:
        c.setFillColor(GREEN); c.setFont("Helvetica", 10)
        c.drawString(40, y, "No violations detected. Package conforms to the Legal Metrology (PC) Rules, 2011."); y -= 14
    for fchk in fails:
        if y < 80:
            c.showPage(); y = H - 60
        c.setFillColor(RED); c.setFont("Helvetica-Bold", 9)
        c.drawString(40, y, f"\u25aa {fchk['title']} \u2014 {fchk['rule_ref']}")
        y -= 12
        c.setFillColor(HexColor("#444444")); c.setFont("Helvetica", 8.6)
        c.drawString(52, y, "Prescribed corrective action: " + (fchk.get("fix") or "Rectify declaration."))
        y -= 11
        c.setFillColor(GREY); c.setFont("Helvetica-Oblique", 8)
        c.drawString(52, y, "Penalty exposure: prosecution/compounding u/s 36 read with s.48, Legal Metrology Act, 2009 (offence-wise).")
        y -= 14

    # footer
    c.setStrokeColor(LINE); c.line(40, 70, W-40, 70)
    c.setFillColor(GREY); c.setFont("Helvetica", 8)
    c.drawString(40, 58, "System-generated report by LegalEye (SIH26034 prototype). Verify against the latest text of the Rules before prosecution.")
    c.drawString(40, 46, "Inspector / Officer signature: ______________________        Seal: ____________")
    c.showPage(); c.save()
    buf.seek(0)
    return buf.read()
