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
        elif spec.dataset_id == "E06SCT_L4_AWV6HOURLY":
            # Product ships u/v wind components; compute speed and direction
            if "u" not in variables or "v" not in variables:
                raise ValueError("AWV6HOURLY product is missing required u and/or v variables")
            if "lat" not in variables or "lon" not in variables or "time" not in variables:
                raise ValueError("Product is missing required latitude, longitude, or time variable")
            latitudes = np.asarray(variables["lat"].data)
            longitudes = np.asarray(variables["lon"].data)
            lat_index = _nearest_index(latitudes, latitude) if latitude is not None else len(latitudes) // 2
            lon_index = _nearest_index(longitudes, longitude) if longitude is not None else len(longitudes) // 2
            u_var = variables["u"]
            v_var = variables["v"]
            u_dims = tuple(u_var.dimensions)
            u_indices = tuple(
                0 if d in {"time", "lev"} else lat_index if d == "lat" else lon_index if d == "lon" else 0
                for d in u_dims
            )
            u_val = _scalar_value(u_var, u_indices)
            v_val = _scalar_value(v_var, u_indices)
            if u_val is not None and v_val is not None:
                speed = math.hypot(u_val, v_val)
                direction = (270.0 - math.degrees(math.atan2(v_val, u_val))) % 360.0
                if not (0.0 <= speed <= 60.0):
                    speed = None
                    direction = None
            else:
                speed = None
                direction = None
            time_variable = variables["time"]
            observed_at = _parse_time(float(np.asarray(time_variable.data).reshape(-1)[0]), _text(_attrs(time_variable)["units"]))
            return {
                "dataset_id": spec.dataset_id,
                "provider": "MOSDAC",
                "product_name": spec.product_name,
                "variable": "wind_speed",
                "value": speed,
                "unit": "m/s",
                "wind_direction": direction,
                "wind_direction_unit": "degrees",
                "latitude": float(latitudes[lat_index]),
                "longitude": float(longitudes[lon_index]),
                "observed_at": observed_at,
                "quality": "unavailable" if speed is None else "computed_from_uv",
                "quality_flag": None,
                "source": "MOSDAC",
                "source_url": None,
                "processing_level": spec.dataset_id.split("_")[1] if "_" in spec.dataset_id else None,
                "resolution": spec.spatial_resolution,
                "raw_file_reference": str(raw_file),
                "parser_version": PARSER_VERSION,
                "metadata": {key: _text(value) for key, value in dataset._attributes.items()},
            }
        elif spec.dataset_id == "E06OCM_L3_LAC_CQ":
            # Schema discovery: find the first science variable (skip coordinates)
            coord_names = {"lat", "lon", "time", "lev", "latitude", "longitude", "depth"}
            science_vars = [name for name in variables if name.lower() not in coord_names and len(variables[name].dimensions) >= 2]
            if not science_vars:
                raise ValueError("LAC_CQ product has no discoverable science variables")
            variable_name = science_vars[0]
        else:
            variable_name = ""

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


def _walk_hdf5_datasets(group: Any, prefix: str = "") -> Dict[str, Any]:
    """Recursively walk HDF5 groups and collect all datasets."""
    found = {}
    for key in group.keys():
        path = f"{prefix}/{key}" if prefix else key
        item = group[key]
        if isinstance(item, h5py.Dataset):
            found[path] = item
        elif isinstance(item, h5py.Group):
            found.update(_walk_hdf5_datasets(item, path))
    return found


def _hdf5_scalar(dataset: Any, indices: tuple, fill_values: set) -> Optional[float]:
    """Extract a scalar from an HDF5 dataset, applying scale/offset."""
    value = float(np.asarray(dataset[indices]).squeeze())
    if not math.isfinite(value) or value in fill_values:
        return None
    scale = float(dataset.attrs.get("scale_factor", dataset.attrs.get("Scale", 1.0)))
    offset = float(dataset.attrs.get("add_offset", dataset.attrs.get("Offset", 0.0)))
    return value * scale + offset


def _find_hdf5_fill(dataset: Any) -> set:
    """Collect fill/missing sentinel values from HDF5 dataset attributes."""
    fills = set()
    for key in ("_FillValue", "missing_value", "Fillvalue", "FillValue"):
        if key in dataset.attrs:
            try:
                fills.add(float(dataset.attrs[key]))
            except (TypeError, ValueError):
                pass
    return fills


def _parse_hdf5_wind(spec: Any, raw_file: Path, latitude: Optional[float], longitude: Optional[float]) -> Dict[str, Any]:
    """Parse MOSDAC HDF5 wind products (L3 WW12 gridded wind vectors)."""
    with h5py.File(raw_file, "r") as hf:
        all_datasets = _walk_hdf5_datasets(hf)

        # Find wind speed and direction datasets
        speed_key = None
        direction_key = None
        for path in all_datasets:
            lower = path.lower()
            if "wind_speed" in lower or "windspeed" in lower:
                if "ascending" in lower and speed_key is None:
                    speed_key = path
                elif "descending" in lower and speed_key is not None:
                    pass  # prefer ascending
                elif speed_key is None:
                    speed_key = path
            if "wind_direction" in lower or "winddir" in lower:
                if "ascending" in lower and direction_key is None:
                    direction_key = path
                elif "descending" in lower and direction_key is not None:
                    pass
                elif direction_key is None:
                    direction_key = path

        if speed_key is None:
            # Try the known science_data structure
            for path in all_datasets:
                if "Ascending_wind_speed" in path:
                    speed_key = path
                if "Ascending_wind_direction" in path:
                    direction_key = path

        if speed_key is None:
            raise ValueError(f"HDF5 product has no wind speed dataset. Available: {list(all_datasets.keys())}")

        speed_ds = all_datasets[speed_key]
        shape = speed_ds.shape

        # Find or construct lat/lon
        lat_key = None
        lon_key = None
        for path in all_datasets:
            lower = path.lower()
            if lower.endswith("latitude") or lower.endswith("lat"):
                lat_key = path
            if lower.endswith("longitude") or lower.endswith("lon"):
                lon_key = path

        if lat_key and lon_key:
            latitudes = np.asarray(all_datasets[lat_key][()]).flatten()
            longitudes = np.asarray(all_datasets[lon_key][()]).flatten()
            # Apply scale/offset if present
            for attr_key in ("scale_factor", "Scale"):
                if attr_key in all_datasets[lat_key].attrs:
                    latitudes = latitudes * float(all_datasets[lat_key].attrs[attr_key])
                if attr_key in all_datasets[lon_key].attrs:
                    longitudes = longitudes * float(all_datasets[lon_key].attrs[attr_key])
            for attr_key in ("add_offset", "Offset"):
                if attr_key in all_datasets[lat_key].attrs:
                    latitudes = latitudes + float(all_datasets[lat_key].attrs[attr_key])
                if attr_key in all_datasets[lon_key].attrs:
                    longitudes = longitudes + float(all_datasets[lon_key].attrs[attr_key])
        else:
            # Construct synthetic grid from shape and global attributes
            n_lat = shape[-2] if len(shape) >= 2 else shape[0]
            n_lon = shape[-1] if len(shape) >= 2 else shape[-1]
            lat_start = float(hf.attrs.get("lat_start", hf.attrs.get("Latitude_Start", -90.0)))
            lat_end = float(hf.attrs.get("lat_end", hf.attrs.get("Latitude_End", 90.0)))
            lon_start = float(hf.attrs.get("lon_start", hf.attrs.get("Longitude_Start", 0.0)))
            lon_end = float(hf.attrs.get("lon_end", hf.attrs.get("Longitude_End", 360.0)))
            latitudes = np.linspace(lat_start, lat_end, n_lat)
            longitudes = np.linspace(lon_start, lon_end, n_lon)

        # Find nearest cell
        if latitude is not None:
            flat_lat = latitudes.flatten() if latitudes.ndim > 1 else latitudes
            lat_index = int(np.nanargmin(np.abs(flat_lat.astype(float) - latitude)))
        else:
            lat_index = len(latitudes) // 2
        if longitude is not None:
            flat_lon = longitudes.flatten() if longitudes.ndim > 1 else longitudes
            lon_index = int(np.nanargmin(np.abs(flat_lon.astype(float) - longitude)))
        else:
            lon_index = len(longitudes) // 2

        # Extract wind speed
        speed_fills = _find_hdf5_fill(speed_ds)
        if len(shape) == 2:
            indices = (lat_index, lon_index)
        elif len(shape) == 3:
            indices = (0, lat_index, lon_index)
        else:
            indices = (lat_index, lon_index)
        speed_val = _hdf5_scalar(speed_ds, indices, speed_fills)

        # Extract wind direction if available
        direction_val = None
        if direction_key:
            dir_ds = all_datasets[direction_key]
            dir_fills = _find_hdf5_fill(dir_ds)
            direction_val = _hdf5_scalar(dir_ds, indices, dir_fills)

        # Validate wind speed range
        if speed_val is not None and not (0.0 <= speed_val <= 60.0):
            speed_val = None
            direction_val = None

        # Extract time from filename or attributes
        observed_at = None
        # Try global attributes
        for time_attr in ("time", "Time", "start_time", "StartTime", "RangeBeginningDate"):
            if time_attr in hf.attrs:
                try:
                    raw_time = _text(hf.attrs[time_attr])
                    # Try ISO parse
                    observed_at = datetime.fromisoformat(raw_time.replace("Z", "+00:00")).isoformat().replace("+00:00", "Z")
                    break
                except (ValueError, TypeError):
                    pass
        if observed_at is None:
            # Try parsing from filename: e.g., E06SCTL3WW2026255_12km
            fname = raw_file.stem
            match = re.search(r"(\d{4})(\d{3})", fname)
            if match:
                year = int(match.group(1))
                doy = int(match.group(2))
                try:
                    dt = datetime(year, 1, 1, tzinfo=timezone.utc) + timedelta(days=doy - 1)
                    observed_at = dt.isoformat().replace("+00:00", "Z")
                except (ValueError, OverflowError):
                    pass
        if observed_at is None:
            observed_at = "unknown"

        # Collect metadata
        metadata = {}
        for key in hf.attrs:
            try:
                metadata[str(key)] = _text(hf.attrs[key])
            except (TypeError, ValueError):
                pass

        result_lat = float(latitudes[lat_index]) if lat_index < len(latitudes) else None
        result_lon = float(longitudes[lon_index]) if lon_index < len(longitudes) else None

        return {
            "dataset_id": spec.dataset_id,
            "provider": "MOSDAC",
            "product_name": spec.product_name,
            "variable": "wind_speed",
            "value": speed_val,
            "unit": "m/s",
            "wind_direction": direction_val,
            "wind_direction_unit": "degrees",
            "latitude": result_lat,
            "longitude": result_lon,
            "observed_at": observed_at,
            "quality": "unavailable" if speed_val is None else "unfiltered",
            "quality_flag": None,
            "source": "MOSDAC",
            "source_url": None,
            "processing_level": spec.dataset_id.split("_")[1] if "_" in spec.dataset_id else None,
            "resolution": spec.spatial_resolution,
            "raw_file_reference": str(raw_file),
            "parser_version": PARSER_VERSION,
            "metadata": metadata,
        }


def parse_product(spec: Any, raw_file: Path, latitude: Optional[float] = None, longitude: Optional[float] = None) -> Dict[str, Any]:
    raw_file = Path(raw_file)
    if not raw_file.is_file() or raw_file.stat().st_size == 0:
        raise ValueError(f"MOSDAC file is missing or empty: {raw_file}")
    if raw_file.suffix.lower() == ".h5":
        return _parse_hdf5_wind(spec, raw_file, latitude, longitude)
    return _netcdf_observation(spec, raw_file, latitude, longitude)
