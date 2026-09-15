class AdvisoryHistoryItem {
  final String id;
  final String advisoryId;
  final String locationName;
  final double latitude;
  final double longitude;
  final String verdict; // GOOD, CAUTION, NO-GO
  final String headline;
  final List<String> majorHazards;
  final DateTime timestamp;
  final String freshnessLabel;

  const AdvisoryHistoryItem({
    required this.id,
    required this.advisoryId,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.verdict,
    required this.headline,
    required this.majorHazards,
    required this.timestamp,
    required this.freshnessLabel,
  });

  factory AdvisoryHistoryItem.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final advisoryId = json['advisory_id']?.toString();
    final lat = (json['latitude'] as num?)?.toDouble();
    final lon = (json['longitude'] as num?)?.toDouble();
    final verdict = json['verdict']?.toString();
    final headline = json['headline']?.toString();
    final timestampValue = json['timestamp'];
    final timestamp = timestampValue is num
        ? DateTime.fromMillisecondsSinceEpoch(timestampValue.toInt() * 1000, isUtc: true)
        : null;
    if (id == null || advisoryId == null || lat == null || lon == null ||
        verdict == null || headline == null || timestamp == null) {
      throw const FormatException('History item missing verified advisory facts.');
    }
    return AdvisoryHistoryItem(
      id: id,
      advisoryId: advisoryId,
      locationName: json['location_name']?.toString() ?? 'Coordinates',
      latitude: lat,
      longitude: lon,
      verdict: verdict,
      headline: headline,
      majorHazards: List<String>.from((json['major_hazards'] as Iterable<dynamic>?) ?? []),
      timestamp: timestamp,
      freshnessLabel: json['freshness_label']?.toString() ?? 'Freshness unavailable',
    );
  }
}
