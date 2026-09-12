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
    return AdvisoryHistoryItem(
      id: (json['id'] as String?) ?? 'hist-${DateTime.now().millisecondsSinceEpoch}',
      advisoryId: (json['advisory_id'] as String?) ?? 'adv-001',
      locationName: (json['location_name'] as String?) ?? 'Veraval Offshore',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 20.9,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 70.37,
      verdict: (json['verdict'] as String?) ?? 'GOOD',
      headline: (json['headline'] as String?) ?? 'Safe to sail',
      majorHazards: List<String>.from((json['major_hazards'] as Iterable<dynamic>?) ?? []),
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as int) * 1000)
          : DateTime.now(),
      freshnessLabel: (json['freshness_label'] as String?) ?? 'Cloud Synced',
    );
  }
}
