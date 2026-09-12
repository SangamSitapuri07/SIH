import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/sync/sync_manager.dart';
import '../../domain/saved_location.dart';

final savedLocationsProvider = StateNotifierProvider<SavedLocationsNotifier, List<SavedLocation>>((ref) {
  final syncManager = ref.watch(syncManagerProvider.notifier);
  return SavedLocationsNotifier(syncManager);
});

class SavedLocationsNotifier extends StateNotifier<List<SavedLocation>> {
  final SyncManager _syncManager;

  SavedLocationsNotifier(this._syncManager)
      : super([
          const SavedLocation(
            id: 'loc-1',
            name: 'Home Harbour (Veraval)',
            latitude: 20.9,
            longitude: 70.37,
            category: 'Harbour',
            isFavourite: true,
            notes: 'Main departure and landing harbour',
          ),
          const SavedLocation(
            id: 'loc-2',
            name: 'Offshore Fishing Zone A',
            latitude: 20.75,
            longitude: 70.2,
            category: 'Fishing Area',
            isFavourite: true,
            notes: 'High yield Mackerel grounds',
          ),
          const SavedLocation(
            id: 'loc-3',
            name: 'Coastal Shelf Zone B',
            latitude: 20.85,
            longitude: 70.5,
            category: 'Fishing Area',
            isFavourite: false,
            notes: 'Shallow current waters',
          ),
        ]);

  void addLocation(String name, double lat, double lon, String category) {
    final loc = SavedLocation(
      id: 'loc-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      latitude: lat,
      longitude: lon,
      category: category,
      isFavourite: false,
    );
    state = [loc, ...state];
    _syncManager.enqueue('saved_locations', 'CREATE', loc.toJson());
  }

  void toggleFavourite(String id) {
    state = [
      for (final loc in state)
        if (loc.id == id) loc.copyWith(isFavourite: !loc.isFavourite) else loc
    ];
  }

  void deleteLocation(String id) {
    state = state.where((loc) => loc.id != id).toList();
    _syncManager.enqueue('saved_locations', 'DELETE', {'id': id});
  }
}
