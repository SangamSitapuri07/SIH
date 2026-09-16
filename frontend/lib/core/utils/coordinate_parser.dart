/// A coordinate explicitly supplied in conversational text.
class ParsedCoordinate {
  final double latitude;
  final double longitude;

  const ParsedCoordinate(this.latitude, this.longitude);
}

/// Parses deliberate coordinate forms without mistaking ordinary numeric
/// questions (wave heights, dates, distances) for a location.
///
/// Supported examples:
/// - `19.52°N 71.50°E`
/// - `19.52 N, 71.50 E`
/// - `19.52, 71.50`
/// - `lat 19.52 lon 71.50`
ParsedCoordinate? parseCoordinateFromText(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final hemispherePair = RegExp(
    r'([+-]?\d{1,2}(?:\.\d+)?)\s*°?\s*([NS])\s*[,;/\s]+\s*([+-]?\d{1,3}(?:\.\d+)?)\s*°?\s*([EW])',
    caseSensitive: false,
  ).firstMatch(text);
  if (hemispherePair != null) {
    final rawLat = double.tryParse(hemispherePair.group(1)!);
    final rawLon = double.tryParse(hemispherePair.group(3)!);
    if (rawLat == null || rawLon == null) return null;
    final latitude = hemispherePair.group(2)!.toUpperCase() == 'S'
        ? -rawLat.abs()
        : rawLat.abs();
    final longitude = hemispherePair.group(4)!.toUpperCase() == 'W'
        ? -rawLon.abs()
        : rawLon.abs();
    return _validated(latitude, longitude);
  }

  final labelledPair = RegExp(
    r'lat(?:itude)?\s*[:=]?\s*([+-]?\d{1,2}(?:\.\d+)?)\D+lon(?:gitude)?\s*[:=]?\s*([+-]?\d{1,3}(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(text);
  if (labelledPair != null) {
    return _validated(
      double.parse(labelledPair.group(1)!),
      double.parse(labelledPair.group(2)!),
    );
  }

  // A comma is required for an unlabelled decimal pair so ordinary phrases
  // such as "waves 2.5 m wind 15 kn" cannot silently move the location.
  final commaPair = RegExp(
    r'(?:^|[^\d.])([+-]?\d{1,2}(?:\.\d+)?)\s*°?\s*,\s*([+-]?\d{1,3}(?:\.\d+)?)\s*°?(?:$|[^\d.])',
  ).firstMatch(text);
  if (commaPair != null) {
    return _validated(
      double.parse(commaPair.group(1)!),
      double.parse(commaPair.group(2)!),
    );
  }
  return null;
}

ParsedCoordinate? _validated(double latitude, double longitude) {
  if (!latitude.isFinite || !longitude.isFinite) return null;
  if (latitude.abs() > 90 || longitude.abs() > 180) return null;
  return ParsedCoordinate(latitude, longitude);
}
