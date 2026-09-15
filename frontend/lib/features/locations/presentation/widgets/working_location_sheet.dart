import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../advisory/presentation/providers/advisory_provider.dart';
import '../../domain/saved_location.dart';
import '../providers/locations_provider.dart';

/// Sheet that sets the working coordinate used by the real ORCA endpoints.
///
/// Only coordinates the skipper actually chose (device fix, a saved location or
/// typed values) can become the working location — there is no default
/// harbour baked into the UI.
Future<void> showWorkingLocationSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: OrcaTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _WorkingLocationSheet(),
  );
}

class _WorkingLocationSheet extends ConsumerStatefulWidget {
  const _WorkingLocationSheet();

  @override
  ConsumerState<_WorkingLocationSheet> createState() => _WorkingLocationSheetState();
}

class _WorkingLocationSheetState extends ConsumerState<_WorkingLocationSheet> {
  final TextEditingController _lat = TextEditingController();
  final TextEditingController _lon = TextEditingController();
  String? _error;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final Map<String, double> current = ref.read(advisoryLocationProvider);
    _lat.text = (current['lat'] ?? 0).toStringAsFixed(4);
    _lon.text = (current['lon'] ?? 0).toStringAsFixed(4);
  }

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<SavedLocation> saved = ref.watch(savedLocationsProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 16,
          bottom: 18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: OrcaTheme.cardBorderStrong,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const OrcaEyebrow('WORKING LOCATION', color: OrcaTheme.accentDark),
              const SizedBox(height: 6),
              const Text('Which water are we watching?', style: OrcaType.cardTitle),
              const SizedBox(height: 6),
              Text(
                'Every ORCA request is evaluated for this coordinate. Saved harbours, a device fix and typed coordinates all send real values to the ORCA Box.',
                style: OrcaType.body.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _locating ? null : _useDeviceLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2, color: OrcaTheme.accent),
                      )
                    : const Icon(Icons.my_location_rounded, size: 17),
                label: Text(_locating ? 'Reading device location…' : 'Use my device location'),
              ),
              const SizedBox(height: 16),
              const OrcaEyebrow('SAVED LOCATIONS', color: OrcaTheme.textMuted),
              const SizedBox(height: 8),
              if (saved.isEmpty)
                const OrcaUnavailable(
                  icon: Icons.bookmark_border_rounded,
                  title: 'No saved locations yet',
                  message: 'Add harbours or fishing areas from the saved locations screen, or type coordinates below.',
                  compact: true,
                )
              else
                Column(
                  children: <Widget>[
                    for (final SavedLocation location in saved)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const OrcaIconBadge(icon: Icons.place_outlined),
                        title: Text(
                          location.name,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${location.category} · ${location.latitude.toStringAsFixed(3)}, ${location.longitude.toStringAsFixed(3)}',
                          style: OrcaType.caption,
                        ),
                        onTap: () => _apply(location.latitude, location.longitude),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              const OrcaEyebrow('COORDINATES', color: OrcaTheme.textMuted),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Latitude'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lon,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Longitude'),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!, style: OrcaType.caption.copyWith(color: OrcaTheme.textPrimary)),
              ],
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _applyTyped,
                      child: const Text('Use this location'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _useDeviceLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _error = 'Location services are disabled on this device.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _error = 'Location permission was not granted.');
        return;
      }
      final Position position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _lat.text = position.latitude.toStringAsFixed(4);
        _lon.text = position.longitude.toStringAsFixed(4);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Device location could not be read: $error');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _applyTyped() {
    final double? lat = double.tryParse(_lat.text.trim());
    final double? lon = double.tryParse(_lon.text.trim());
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      setState(() => _error = 'Enter valid coordinates within ±90 latitude and ±180 longitude.');
      return;
    }
    _apply(lat, lon);
  }

  void _apply(double lat, double lon) {
    ref.read(advisoryLocationProvider.notifier).state = <String, double>{'lat': lat, 'lon': lon};
    Navigator.pop(context);
  }
}
