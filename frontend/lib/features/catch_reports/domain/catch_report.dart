class CatchReport {
  final String id;
  final String locationName;
  final double latitude;
  final double longitude;
  final String species;
  final double quantityKg;
  final String catchDate;
  final String? notes;
  final bool isSynced;

  const CatchReport({
    required this.id,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.species,
    required this.quantityKg,
    required this.catchDate,
    this.notes,
    this.isSynced = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_name': locationName,
      'latitude': latitude,
      'longitude': longitude,
      'species': species,
      'quantity_kg': quantityKg,
      'catch_date': catchDate,
      'notes': notes,
      'is_synced': isSynced,
    };
  }
}
