import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/sync/sync_manager.dart';
import '../../domain/saved_location.dart';

final savedLocationsProvider = StateNotifierProvider<SavedLocationsNotifier, List<SavedLocation>>((ref) {
  final syncManager = ref.watch(syncManagerProvider.notifier);
  return SavedLocationsNotifier(syncManager);
});

class SavedLocationsNotifier extends StateNotifier<List<SavedLocation>> {
  final SyncManager _syncManager;

  SavedLocationsNotifier(this._syncManager) : super(const <SavedLocation>[]);

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
