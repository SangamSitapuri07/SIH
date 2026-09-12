"""Format-aware parsers for locally retrieved MOSDAC products."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Optional
import math
import re

import h5py
import numpy as np
from scipy.io import netcdf_file


PARSER_VERSION = "1.0.0"


def _text(value: Any) -> str:
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def _attrs(variable: Any) -> Dict[str, Any]:
    return {str(key): value for key, value in variable._attributes.items()}


def _parse_time(value: float, units: str) -> str:
    match = re.match(r"(?P<unit>\w+) since (?P<origin>.+)", units.strip(), re.IGNORECASE)
    if not match:
        raise ValueError(f"Unsupported time units: {units}")
    origin = match.group("origin").strip()
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"):
        try:
            base = datetime.strptime(origin, fmt).replace(tzinfo=timezone.utc)
            break
        except ValueError:
            continue
    else:
        for fmt in ("%d-%m-%Y %H:%M", "%d-%m-%Y %H:%M:%S"):
            try:
                base = datetime.strptime(origin, fmt).replace(tzinfo=timezone.utc)
                break
            except ValueError:
                continue
        else:
            raise ValueError(f"Unsupported time origin: {origin}")
    unit = match.group("unit").lower()
    seconds_per_unit = {"second": 1, "seconds": 1, "hour": 3600, "hours": 3600, "day": 86400, "days": 86400}
    if unit not in seconds_per_unit:
        raise ValueError(f"Unsupported time unit: {unit}")
    return (base + timedelta(seconds=float(value) * seconds_per_unit[unit])).isoformat().replace("+00:00", "Z")


def _nearest_index(values: np.ndarray, target: float) -> int:
    if target < float(np.nanmin(values)) or target > float(np.nanmax(values)):
        raise ValueError("Requested coordinate is outside product coverage")
    return int(np.nanargmin(np.abs(values.astype(float) - target)))


def _scalar_value(variable: Any, indices: tuple[int, ...]) -> Optional[float]:
    value = float(np.asarray(variable[indices]).squeeze())
    attrs = _attrs(variable)
    missing = {float(attrs[key]) for key in ("_FillValue", "missing_value", "Fillvalue") if key in attrs}
    if not math.isfinite(value) or value in missing:
        return None
    scale = float(attrs.get("scale_factor", 1.0))
    offset = float(attrs.get("add_offset", 0.0))
    return value * scale + offset


def _netcdf_observation(spec: Any, raw_file: Path, latitude: Optional[float], longitude: Optional[float]) -> Dict[str, Any]:
    with netcdf_file(str(raw_file), "r", mmap=False) as dataset:
        variables = dataset.variables
        if spec.dataset_id == "E06OCM_L4_AC":
            variable_name = "chla"
        elif spec.dataset_id == "E06SCT_L4_UI":
            variable_name = "Upwelling_index"
        elif spec.dataset_id == "E06SCT_L4_AWW6HOURLY":
            variable_name = "wind_speed"
        elif spec.dataset_id == "E06OCM_L3_LAC_CQ":
            variable_name = "water_quality"
        else:
            variable_name = ""

        if spec.dataset_id == "E06SCT_L4_AWW6HOURLY":
            long_names = {_text(_attrs(value).get("long_name", "")) for value in variables.values()}
            if "SIGMA0 VALUES" in long_names:
                raise ValueError("Sample is OSCAT3_GLO sigma0, not E06SCT_L4_AWW6HOURLY")
        if variable_name not in variables:
            raise ValueError(f"Required variable {variable_name!r} is missing")
        if "lat" not in variables or "lon" not in variables or "time" not in variables:
            raise ValueError("Product is missing required latitude, longitude, or time variable")

        latitudes = np.asarray(variables["lat"].data)
        longitudes = np.asarray(variables["lon"].data)
        lat_index = _nearest_index(latitudes, latitude) if latitude is not None else len(latitudes) // 2
        lon_index = _nearest_index(longitudes, longitude) if longitude is not None else len(longitudes) // 2
        data_variable = variables[variable_name]
        dimensions = tuple(data_variable.dimensions)
        indices = tuple(
            0 if dimension in {"time", "lev"} else lat_index if dimension == "lat" else lon_index if dimension == "lon" else 0
            for dimension in dimensions
        )
        value = _scalar_value(data_variable, indices)
        time_variable = variables["time"]
        observed_at = _parse_time(float(np.asarray(time_variable.data).reshape(-1)[0]), _text(_attrs(time_variable)["units"]))
        variable_attrs = _attrs(data_variable)
        return {
            "dataset_id": spec.dataset_id,
            "provider": "MOSDAC",
            "product_name": spec.product_name,
            "variable": variable_name,
            "value": value,
            "unit": _text(variable_attrs.get("units", "unknown")),
            "latitude": float(latitudes[lat_index]),
            "longitude": float(longitudes[lon_index]),
            "observed_at": observed_at,
            "quality": "unavailable" if value is None else "unfiltered",
            "quality_flag": None,
            "source": "MOSDAC",
            "source_url": None,
            "processing_level": spec.dataset_id.split("_")[1] if "_" in spec.dataset_id else None,
            "resolution": spec.spatial_resolution,
            "raw_file_reference": str(raw_file),
            "parser_version": PARSER_VERSION,
            "metadata": {key: _text(value) for key, value in dataset._attributes.items()},
        }


def parse_product(spec: Any, raw_file: Path, latitude: Optional[float] = None, longitude: Optional[float] = None) -> Dict[str, Any]:
    raw_file = Path(raw_file)
    if not raw_file.is_file() or raw_file.stat().st_size == 0:
        raise ValueError(f"MOSDAC file is missing or empty: {raw_file}")
    if raw_file.suffix.lower() == ".h5":
        with h5py.File(raw_file, "r") as dataset:
            required = {
                "science_data/Ascending_wind_direction",
                "science_data/Ascending_wind_speed",
                "science_data/Ascending_wind_quality_flag",
                "science_data/Descending_wind_direction",
                "science_data/Descending_wind_speed",
                "science_data/Descending_wind_quality_flag",
            }
            available = set(dataset.keys())
            if not required.intersection(available) and "science_data" in dataset:
                available = {f"science_data/{name}" for name in dataset["science_data"].keys()}
            if not required.issubset(available):
                raise ValueError("WV12 sample is missing one or more wind-vector variables")
            raise ValueError("WV12 sample lacks latitude, longitude, time, scaling, and product metadata")
    return _netcdf_observation(spec, raw_file, latitude, longitude)
