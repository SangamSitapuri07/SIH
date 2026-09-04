"""Agent 2: Satellite Analysis 🛰️

Processes chlorophyll, ocean colour, and satellite observations
from NOAA ERDDAP, INCOIS LAS, and (later) MOSDAC OCM-3.

Inputs: ZoneSnapshot
Outputs: dict of findings (same shape as ocean agent)
"""
from __future__ import annotations

from typing import Any
import math


def analyze(snap: dict[str, Any]) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []

    chl = snap.get("chlorophyll")
    chl_source = snap.get("chlorophyll_source", "unknown")
    chl_unit = snap.get("chlorophyll_unit", "mg/m^3")

    if chl is None:
        return {
            "agent": "satellite",
            "findings": [{
                "type": "no_chlorophyll_data",
                "severity": "info",
                "value": None,
                "msg": f"No chlorophyll data available from {chl_source or 'any source'}.",
            }],
            "summary": "Chlorophyll data unavailable — ocean color cannot be assessed.",
            "risk_level": "unknown",
        }

    # Chlorophyll interpretation (mg/m^3):
    #  < 0.1  : oligotrophic (very low productivity, blue water)
    #  0.1-0.5: low productivity
    #  0.5-1.5: productive (good for fishing)
    #  1.5-5.0: highly productive (often upwelling zones)
    #  > 5.0  : very high (possible bloom, may be harmful)
    if chl < 0.1:
        sev = "info"
        typ = "chl_oligotrophic"
        msg = f"Chlorophyll {chl:.2f} {chl_unit} — very low productivity (oligotrophic)."
    elif chl < 0.5:
        sev = "info"
        typ = "chl_low"
        msg = f"Chlorophyll {chl:.2f} {chl_unit} — low productivity."
    elif chl < 1.5:
        sev = "good"
        typ = "chl_productive"
        msg = f"Chlorophyll {chl:.2f} {chl_unit} — productive zone, good for fishing."
    elif chl < 5.0:
        sev = "good"
        typ = "chl_high"
        msg = f"Chlorophyll {chl:.2f} {chl_unit} — highly productive (likely upwelling or bloom)."
    else:
        sev = "warn"
        typ = "chl_bloom"
        msg = f"Chlorophyll {chl:.2f} {chl_unit} — very high, possible harmful algal bloom."

    findings.append({
        "type": typ,
        "severity": sev,
        "value": chl,
        "msg": msg,
    })

    # log10 band: classical ocean-color zones
    if chl > 0:
        findings.append({
            "type": "chl_log10",
            "severity": "info",
            "value": round(math.log10(chl), 2),
            "msg": f"log10(chl) = {math.log10(chl):.2f} (ocean color band reference).",
        })

    findings.append({
        "type": "source_attribution",
        "severity": "info",
        "value": chl_source,
        "msg": f"Data source: {chl_source}",
    })

    # Cross-validation: if OC-CCI is also available, compare.
    # If they disagree by >2x, that's a flag — the value is uncertain.
    chl_occci = snap.get("chlorophyll_occci")
    chl_occci_source = snap.get("chlorophyll_occci_source", "ESA OC-CCI")
    if chl_occci is not None and chl > 0:
        ratio = max(chl, chl_occci) / min(chl, chl_occci)
        if ratio > 3.0:
            # >3x disagreement — this is real, surface it
            findings.append({
                "type": "chl_cross_check_disagree",
                "severity": "warn",
                "value": {"primary": chl, "occci": chl_occci, "ratio": round(ratio, 1)},
                "msg": (
                    f"⚠️ Cross-check disagrees: NOAA reports {chl:.2f} but "
                    f"OC-CCI reports {chl_occci:.2f} ({ratio:.1f}x apart). "
                    f"Chlorophyll is highly variable spatially — coastal blooms "
                    f"can be 10-100x higher than offshore water in the same "
                    f"0.2° box."
                ),
            })
        else:
            findings.append({
                "type": "chl_cross_check_ok",
                "severity": "good",
                "value": {"primary": chl, "occci": chl_occci, "ratio": round(ratio, 1)},
                "msg": (
                    f"✓ Cross-check agrees: NOAA {chl:.2f} vs OC-CCI "
                    f"{chl_occci:.2f} ({ratio:.1f}x apart, within 3x)."
                ),
            })
    else:
        # Cross-check absent (usually monsoon cloud cover masking OC-CCI).
        # Say "not cross-validated" explicitly — it is NOT "no data":
        # the primary measurement above is real and drives the risk tag.
        findings.append({
            "type": "chl_cross_check_missing",
            "severity": "info",
            "value": None,
            "msg": (
                "OC-CCI cross-check unavailable (usually monsoon clouds) — "
                "value above is the primary measurement, shown WITHOUT "
                "independent cross-validation."
            ),
        })

    # ISRO MOSDAC OCM-3 live — India's own satellite as a second,
    # INDEPENDENT cross-check (1 km LAC resolution — finer than the
    # primary's global grid). 🇮🇳
    chl_mosdac = snap.get("chlorophyll_mosdac")
    if chl_mosdac is not None and chl > 0:
        ratio_m = max(chl, chl_mosdac) / min(chl, chl_mosdac)
        mosdac_date = snap.get("chlorophyll_mosdac_date") or "latest"
        if ratio_m > 3.0:
            findings.append({
                "type": "chl_mosdac_check_disagree",
                "severity": "warn",
                "value": {"primary": chl, "mosdac": chl_mosdac, "ratio": round(ratio_m, 1)},
                "msg": (
                    f"⚠️ ISRO OCM-3 ({chl_mosdac:.2f}, granule {mosdac_date}) vs primary "
                    f"{chl:.2f} — {ratio_m:.1f}x apart. OCM-3's 1 km pixels see coastal "
                    f"blooms the coarser global grids smear out; treat the fine "
                    f"structure as real, not an error."
                ),
            })
        else:
            findings.append({
                "type": "chl_mosdac_check_ok",
                "severity": "good",
                "value": {"primary": chl, "mosdac": chl_mosdac, "ratio": round(ratio_m, 1)},
                "msg": (
                    f"✓ ISRO OCM-3 agrees: {chl_mosdac:.2f} mg/m³ (granule {mosdac_date}) "
                    f"vs primary {chl:.2f} ({ratio_m:.1f}x, within 3x) — India's own "
                    f"satellite independently confirms the reading. 🇮🇳"
                ),
            })

    # Risk — CENTRAL shared rule (agents.risk_from_findings). Tag comes
    # from the PRIMARY measurement's hazard level — never from whether an
    # optional cross-check source succeeded.
    from pipeline.agents import risk_from_findings
    risk = risk_from_findings(findings, has_data=True)  # chl is not None here

    n_good = sum(1 for f in findings if f["severity"] == "good")
    n_warn = sum(1 for f in findings if f["severity"] in ("warn", "high"))
    if n_warn > 0:
        summary = f"Satellite: chlorophyll shows concerning level ({chl:.2f} {chl_unit})."
    elif n_good > 0:
        summary = f"Satellite: chlorophyll indicates productive zone ({chl:.2f} {chl_unit})."
    else:
        summary = f"Satellite: chlorophyll {chl:.2f} {chl_unit} (low activity)."

    return {
        "agent": "satellite",
        "findings": findings,
        "summary": summary,
        "risk_level": risk,
    }
