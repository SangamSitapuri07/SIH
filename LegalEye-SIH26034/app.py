#!/usr/bin/env python3
"""LegalEye backend — SIH26034 prototype.
FastAPI: sample library, scan pipeline (OCR -> 2011-Rules engine), history,
dashboard stats, PDF reports. All state in JSON files under store/.
"""
import os, io, json, base64, uuid, datetime
import numpy as np
import cv2
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import HTMLResponse, Response, JSONResponse
from fastapi.staticfiles import StaticFiles

BASE = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.join(BASE, "store"); os.makedirs(STORE, exist_ok=True)
RESULTS = os.path.join(STORE, "results"); os.makedirs(RESULTS, exist_ok=True)
HIST = os.path.join(STORE, "history.json")

from rules_engine import analyze
from report_gen import build_pdf

# sample library metadata
SAMPLES = [
    {"key": "biscuits_compliant.png", "name": "KrunchKrust Bourbon Biscuits", "desc": "Retail biscuit pack \u2014 reference compliant pack",
     "package_class": "small", "width_mm": 180, "hint": "Expect: fully compliant"},
    {"key": "shampoo_violations.png", "name": "Verdant Herbals Shampoo 200 ml", "desc": "Personal care bottle",
     "package_class": "small", "width_mm": 130, "hint": "Expect: bare price number, no tax line, weak consumer care"},
    {"key": "atta_violations.png", "name": "GoldenHarvest Atta 5 kg", "desc": "Staple food bag \u2014 large pack",
     "package_class": "large", "width_mm": 215, "hint": "Expect: tiny net-qty font, missing MFD month-year"},
    {"key": "choco_import_violations.png", "name": "ChocoRoyal Imported Wafers", "desc": "Imported confectionery",
     "package_class": "small", "width_mm": 170, "hint": "Expect: no country of origin / no importer"},
    {"key": "namkeen_severe.png", "name": "Tadka Treat Aloo Bhujia", "desc": "Snack pouch",
     "package_class": "small", "width_mm": 200, "hint": "Expect: MRP absent + no veg logo (sale prohibited)"},
]

app = FastAPI(title="LegalEye \u2014 Legal Metrology Compliance Scanner")
app.mount("/static", StaticFiles(directory=os.path.join(BASE, "static")), name="static")

_ocr = None
def get_ocr():
    global _ocr
    if _ocr is None:
        from rapidocr_onnxruntime import RapidOCR
        _ocr = RapidOCR()
    return _ocr

def run_ocr(img_bgr):
    res, _ = get_ocr()(img_bgr)
    return [{"box": r[0], "text": r[1], "conf": float(r[2])} for r in (res or [])]

def load_hist():
    if os.path.exists(HIST):
        try: return json.load(open(HIST))
        except Exception: return []
    return []

def save_hist(h):
    json.dump(h, open(HIST, "w"), indent=1)

def thumb_b64(img_bgr, maxw=220):
    h, w = img_bgr.shape[:2]
    s = maxw / max(w, 1)
    t = cv2.resize(img_bgr, (maxw, max(1, int(h * s))))
    ok, enc = cv2.imencode(".jpg", t, [cv2.IMWRITE_JPEG_QUALITY, 72])
    return base64.b64encode(enc.tobytes()).decode()

def full_b64(img_bgr, maxw=1400):
    h, w = img_bgr.shape[:2]
    if w > maxw:
        s = maxw / w
        img_bgr = cv2.resize(img_bgr, (maxw, int(h * s)))
    ok, enc = cv2.imencode(".jpg", img_bgr, [cv2.IMWRITE_JPEG_QUALITY, 88])
    return base64.b64encode(enc.tobytes()).decode()


@app.get("/", response_class=HTMLResponse)
def index():
    with open(os.path.join(BASE, "static", "index.html")) as f:
        return f.read()

@app.get("/api/samples")
def samples():
    return [{"key": s["key"], "name": s["name"], "desc": s["desc"], "hint": s["hint"],
             "url": f"/static/samples/{s['key']}"} for s in SAMPLES]

@app.post("/api/scan")
async def scan(file: UploadFile = File(None), sample: str = Form(None),
               product_name: str = Form(""), package_class: str = Form("small"),
               label_width_mm: float = Form(180.0)):
    if sample:
        srow = next((s for s in SAMPLES if s["key"] == sample), None)
        if not srow: raise HTTPException(404, "unknown sample")
        img = cv2.imread(os.path.join(BASE, "static", "samples", sample))
        product_name = product_name or srow["name"]
        package_class = srow["package_class"]; label_width_mm = srow["width_mm"]
    else:
        if file is None: raise HTTPException(400, "no image")
        data = await file.read()
        arr = np.frombuffer(data, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None: raise HTTPException(400, "not an image")
        try:
            label_width_mm = max(40.0, min(float(label_width_mm), 800.0))
        except Exception:
            label_width_mm = 180.0
        if package_class not in ("small", "medium", "large", "xlarge"):
            package_class = "small"

    lines = run_ocr(img)
    result = analyze(img, lines, package_class=package_class,
                     label_width_mm=float(label_width_mm), product_name=product_name)
    scan_id = datetime.datetime.now().strftime("%y%m%d") + "-" + uuid.uuid4().hex[:6].upper()
    result["scan_id"] = scan_id
    result["product_name"] = product_name
    result["ts"] = datetime.datetime.now().isoformat(timespec="seconds")
    result["image_b64"] = full_b64(img)
    json.dump(result, open(os.path.join(RESULTS, scan_id + ".json"), "w"))
    h = load_hist()
    h.insert(0, {"id": scan_id, "ts": result["ts"], "product": product_name or "Uploaded pack",
                 "score": result["score"], "grade": result["grade"], "verdict": result["verdict"],
                 "fails": result["failed_checks"], "thumb": thumb_b64(img)})
    save_hist(h[:200])
    return JSONResponse(result)

@app.get("/api/history")
def history():
    return load_hist()[:100]

@app.get("/api/stats")
def stats():
    h = load_hist()
    out = {"total": len(h), "compliant": 0, "minor": 0, "major": 0, "avg": 0, "rules": {}}
    scores = []
    for row in h:
        scores.append(row["score"])
        g = row["grade"]
        out["compliant" if g == "A" else "minor" if g == "B" else "major"] += 1
    out["avg"] = round(sum(scores) / len(scores)) if scores else 0
    # violation frequency from stored results
    for row in h[:60]:
        p = os.path.join(RESULTS, row["id"] + ".json")
        if not os.path.exists(p): continue
        try: r = json.load(open(p))
        except Exception: continue
        for c in r["checks"]:
            if c["status"] == "fail":
                k = c["id"] + " \u00b7 " + c["title"]
                out["rules"][k] = out["rules"].get(k, 0) + 1
    out["rules"] = dict(sorted(out["rules"].items(), key=lambda kv: -kv[1])[:8])
    return out

@app.get("/api/report/{scan_id}.pdf")
def report(scan_id: str):
    p = os.path.join(RESULTS, scan_id + ".json")
    if not os.path.exists(p): raise HTTPException(404, "scan not found")
    r = json.load(open(p))
    pdf = build_pdf(r, r.get("product_name", ""))
    return Response(content=pdf, media_type="application/pdf",
                    headers={"Content-Disposition": f"attachment; filename=LegalEye_{scan_id}.pdf"})

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
