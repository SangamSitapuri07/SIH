class SavedLocation {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String category; // Harbour, Fishing Area, Favorite Spot
  final bool isFavourite;
  final String? notes;

  const SavedLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.category = 'Fishing Area',
    this.isFavourite = false,
    this.notes,
  });

  factory SavedLocation.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final name = json['name']?.toString();
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    if (id == null || name == null || name.trim().isEmpty || latitude == null || longitude == null) {
      throw const FormatException('Saved location is missing a name or coordinates.');
    }
    return SavedLocation(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
      category: json['category']?.toString() ?? 'Uncategorized',
      isFavourite: json['is_favourite'] as bool? ?? false,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'category': category,
      'is_favourite': isFavourite,
      'notes': notes,
    };
  }

  SavedLocation copyWith({
    String? name,
    double? latitude,
    double? longitude,
    String? category,
    bool? isFavourite,
    String? notes,
  }) {
    return SavedLocation(
      id: id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      category: category ?? this.category,
      isFavourite: isFavourite ?? this.isFavourite,
      notes: notes ?? this.notes,
    );
  }
}
