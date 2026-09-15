import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/widgets/orca_navigation.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../advisory/presentation/providers/advisory_provider.dart';
import '../../../locations/domain/saved_location.dart';
import '../../../locations/presentation/providers/locations_provider.dart';
import '../providers/navigate_provider.dart';
import '../widgets/route_verdict_card.dart';
import '../widgets/transit_points_strip.dart';

/// Route planner and transit verifier.
///
/// The planner only accepts real coordinates (typed, picked from the working
/// location or from a saved location). Results come from `/api/v1/route-check`
/// and `/api/v1/route-advisory`; the screen starts empty and never prefills a
/// harbour, a detour or a verdict.
class NavigateScreen extends ConsumerStatefulWidget {
  const NavigateScreen({super.key});

  @override
  ConsumerState<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends ConsumerState<NavigateScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _fromLat = TextEditingController();
  final TextEditingController _fromLon = TextEditingController();
  final TextEditingController _toLat = TextEditingController();
  final TextEditingController _toLon = TextEditingController();
  String? _formMessage;

  @override
  void initState() {
    super.initState();
    // The departure defaults to the working location because that is the real
    // coordinate this device is already watching — the fields stay editable and
    // the result is only produced when the skipper asks for it.
    final Map<String, double> coords = ref.read(advisoryLocationProvider);
    _fromLat.text = (coords['lat'] ?? AppConfig.defaultLat).toStringAsFixed(4);
    _fromLon.text = (coords['lon'] ?? AppConfig.defaultLon).toStringAsFixed(4);
  }

  @override
  void dispose() {
    _fromLat.dispose();
    _fromLon.dispose();
    _toLat.dispose();
    _toLon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<RouteAnalysisState> state = ref.watch(navigateProvider);

    return OrcaWorkspaceScaffold(
      title: AppLocalizations.of(context)?.navigateTitle ?? 'Route planner',
      subtitle: 'Course verification and sampled transit',
      locationLabel: 'Departure',
      coordinateLabel: _departureLabel(),
      stateLabel: state.hasValue && state.valueOrNull?.advisory != null ? 'RESULT READY' : null,
      onRefresh: () async {
        // The refresh control re-runs the check when the form is valid, so the
        // button always performs a real backend request rather than a no-op.
        if (_formKey.currentState?.validate() ?? false) _checkRoute();
      },
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool twoColumn = constraints.maxWidth > OrcaTheme.compactBreakpoint;
          final Widget planner = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const OrcaEyebrow('TRIP PLANNING', color: OrcaTheme.accentDark),
              const SizedBox(height: 6),
              Text('Know the route before you cast off.', style: OrcaType.displayCompact),
              const SizedBox(height: 8),
              Text(
                'Enter departure and destination coordinates. ORCA samples the real marine inputs along the leg and reports land clearance only when a verified land-mask source answers.',
                style: OrcaType.body.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 18),
              _RouteForm(
                formKey: _formKey,
                fromLat: _fromLat,
                fromLon: _fromLon,
                toLat: _toLat,
                toLon: _toLon,
                message: _formMessage,
                onUseWorkingLocation: _useWorkingLocation,
                onPickSaved: _pickSavedLocation,
                onCheck: _checkRoute,
              ),
              const SizedBox(height: 14),
              const _TimeContractNote(),
            ],
          );

          final Widget results = state.when(
            data: (RouteAnalysisState data) => data.advisory == null
                ? const _RouteEmpty()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const OrcaEyebrow('ROUTE SAFETY RESULT', color: OrcaTheme.textMuted),
                      const SizedBox(height: 10),
                      RouteVerdictCard(advisory: data.advisory!, check: data.check),
                      const SizedBox(height: 16),
                      TransitPointsStrip(points: data.advisory!.points),
                    ],
                  ),
            loading: () => const _RouteLoading(),
            error: (Object? error, StackTrace? stack) => OrcaUnavailable(
              icon: Icons.cloud_off_outlined,
              title: 'Route safety unavailable',
              message: 'ORCA could not verify the required route inputs. $error',
              actionLabel: 'Retry',
              onAction: _checkRoute,
            ),
          );

          final Widget body = ListView(
            padding: orcaContentPadding(wide: twoColumn),
            children: <Widget>[
              if (twoColumn)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 5, child: planner),
                    const SizedBox(width: 20),
                    Expanded(flex: 6, child: results),
                  ],
                )
              else ...<Widget>[
                planner,
                const SizedBox(height: 20),
                results,
              ],
            ],
          );

          return body;
        },
      ),
    );
  }

  String _departureLabel() {
    final double? lat = double.tryParse(_fromLat.text.trim());
    final double? lon = double.tryParse(_fromLon.text.trim());
    if (lat == null || lon == null) return 'Coordinates not set';
    return GeoUtils.formatCoordinate(lat, lon);
  }

  void _useWorkingLocation() {
    final Map<String, double> coords = ref.read(advisoryLocationProvider);
    setState(() {
      _fromLat.text = (coords['lat'] ?? AppConfig.defaultLat).toStringAsFixed(4);
      _fromLon.text = (coords['lon'] ?? AppConfig.defaultLon).toStringAsFixed(4);
      _formMessage = 'Departure set to the working location.';
    });
  }

  Future<void> _pickSavedLocation({required bool asDeparture}) async {
    final List<SavedLocation> saved = ref.read(savedLocationsProvider);
    if (saved.isEmpty) {
      setState(() => _formMessage =
          'No saved locations yet. Save a harbour or fishing area first, or enter coordinates directly.');
      return;
    }
    final SavedLocation? picked = await showModalBottomSheet<SavedLocation>(
      context: context,
      backgroundColor: OrcaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: <Widget>[
            const OrcaEyebrow('SAVED LOCATIONS', color: OrcaTheme.accentDark),
            const SizedBox(height: 8),
            for (final SavedLocation location in saved)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const OrcaIconBadge(icon: Icons.place_outlined),
                title: Text(location.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                subtitle: Text(
                  '${location.latitude.toStringAsFixed(3)}, ${location.longitude.toStringAsFixed(3)}',
                  style: OrcaType.caption,
                ),
                onTap: () => Navigator.pop(sheetContext, location),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (asDeparture) {
        _fromLat.text = picked.latitude.toStringAsFixed(4);
        _fromLon.text = picked.longitude.toStringAsFixed(4);
      } else {
        _toLat.text = picked.latitude.toStringAsFixed(4);
        _toLon.text = picked.longitude.toStringAsFixed(4);
      }
      _formMessage = null;
    });
  }

  void _checkRoute() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _formMessage = null);
    ref.read(navigateProvider.notifier).evaluateRoute(
          fromLat: double.parse(_fromLat.text.trim()),
          fromLon: double.parse(_fromLon.text.trim()),
          toLat: double.parse(_toLat.text.trim()),
          toLon: double.parse(_toLon.text.trim()),
        );
  }
}

class _RouteForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController fromLat;
  final TextEditingController fromLon;
  final TextEditingController toLat;
  final TextEditingController toLon;
  final String? message;
  final VoidCallback onUseWorkingLocation;
  final void Function({required bool asDeparture}) onPickSaved;
  final VoidCallback onCheck;

  const _RouteForm({
    required this.formKey,
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.message,
    required this.onUseWorkingLocation,
    required this.onPickSaved,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return OrcaCard(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OrcaEyebrow('DEPARTURE', color: OrcaTheme.textMuted),
            const SizedBox(height: 8),
            _CoordinateRow(lat: fromLat, lon: fromLon),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: onUseWorkingLocation,
                  icon: const Icon(Icons.my_location_rounded, size: 15),
                  label: const Text('Working location'),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
                TextButton.icon(
                  onPressed: () => onPickSaved(asDeparture: true),
                  icon: const Icon(Icons.bookmark_border_rounded, size: 15),
                  label: const Text('Saved place'),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: OrcaTheme.cardBorder),
            ),
            const OrcaEyebrow('DESTINATION', color: OrcaTheme.textMuted),
            const SizedBox(height: 8),
            _CoordinateRow(lat: toLat, lon: toLon),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: () => onPickSaved(asDeparture: false),
                  icon: const Icon(Icons.bookmark_border_rounded, size: 15),
                  label: const Text('Saved place'),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ],
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(message!, style: OrcaType.caption.copyWith(fontSize: 11.5)),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onCheck,
              icon: const Icon(Icons.route_outlined, size: 18),
              label: const Text('Check route safety'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordinateRow extends StatelessWidget {
  final TextEditingController lat;
  final TextEditingController lon;

  const _CoordinateRow({required this.lat, required this.lon});

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: TextFormField(
              controller: lat,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Latitude'),
              validator: _validateLatitude,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: lon,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Longitude'),
              validator: _validateLongitude,
            ),
          ),
        ],
      );

  static String? _validateLatitude(String? value) {
    final double? parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || !parsed.isFinite) return 'Enter a latitude';
    if (parsed.abs() > 90) return 'Latitude must be within ±90°';
    return null;
  }

  static String? _validateLongitude(String? value) {
    final double? parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || !parsed.isFinite) return 'Enter a longitude';
    if (parsed.abs() > 180) return 'Longitude must be within ±180°';
    return null;
  }
}

class _TimeContractNote extends StatelessWidget {
  const _TimeContractNote();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: OrcaTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline_rounded, size: 16, color: OrcaTheme.accentDark),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Departure-time routing is unavailable: the current backend contract evaluates present route conditions only. ORCA will expose a time selector when a verified route forecast contract exists.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.5,
                  height: 1.45,
                  color: OrcaTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
}

class _RouteEmpty extends StatelessWidget {
  const _RouteEmpty();

  @override
  Widget build(BuildContext context) => const OrcaUnavailable(
        icon: Icons.route_outlined,
        title: 'No route checked yet',
        message: 'Enter both coordinates and run the check. ORCA reports the sampled marine conditions and the land-verification state of this exact response — nothing is prefilled or assumed.',
      );
}

class _RouteLoading extends StatelessWidget {
  const _RouteLoading();

  @override
  Widget build(BuildContext context) => OrcaCard(
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: OrcaTheme.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sampling marine inputs along the leg and verifying land clearance…',
                style: OrcaType.body.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
}
