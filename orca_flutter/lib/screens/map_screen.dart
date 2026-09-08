import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../marine.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class MapScreen extends StatefulWidget {
  final Settings settings;
  final AppState app;
  const MapScreen({super.key, required this.settings, required this.app});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _ctrl = MapController();
  LatLng _center = const LatLng(20.9, 70.37); // Veraval default
  Map<String, dynamic>? _field;
  String? _err;
  bool _loading = false, _seaMarks = false;
  double _zoom = 9.5;

  @override
  void initState() {
    super.initState();
    final f = widget.app.lastFix;
    if (f != null) _center = LatLng(f.latitude, f.longitude);
    _load(_center);
  }

  Future<void> _load(LatLng c) async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final data =
          await OrcaApi.field(widget.settings.base, c.latitude, c.longitude);
      final p = await SharedPreferences.getInstance();
      await p.setString(
          'pack_field',
          jsonEncode(
              {'ts': DateTime.now().toIso8601String(), 'data': data}));
      if (mounted) setState(() {
        _field = data;
        _loading = false;
      });
    } catch (e) {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('pack_field');
      if (raw != null) {
        try {
          final pack = jsonDecode(raw) as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _field = pack['data'] as Map<String, dynamic>;
              _loading = false;
            });
          }
          return;
        } catch (_) {}
      }
      if (mounted) setState(() {
        _err = '$e';
        _loading = false;
      });
    }
  }

  List get _hotspots => (_field?['hotspots'] as List?) ?? const [];
  List get _metPoints =>
      ((_field?['met'] as Map?)?['points'] as List?) ?? const [];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final myFix = widget.app.lastFix;
    return Stack(children: [
      FlutterMap(
        mapController: _ctrl,
        options: MapOptions(
          initialCenter: _center,
          initialZoom: _zoom,
          onMapReady: () => _ctrl.move(_center, _zoom),
          onLongPress: (tap, ll) => _inspectPoint(ll),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'in.sih2026.orca',
          ),
          if (_seaMarks)
            TileLayer(
              urlTemplate:
                  'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
              userAgentPackageName: 'in.sih2026.orca',
            ),
          // met grid dots (live data cells; on-land cells grey — honest)
          CircleLayer(circles: [
            for (final p in _metPoints)
              CircleMarker(
                point: LatLng((p['lat'] as num).toDouble(),
                    (p['lon'] as num).toDouble()),
                radius: 3.4,
                color: (p['land'] == true)
                    ? Colors.grey.withOpacity(0.5)
                    : OrcaTheme.teal.withOpacity(0.65),
              ),
          ]),
          // my location
          if (myFix != null) ...[
            CircleLayer(circles: [
              CircleMarker(
                point: LatLng(myFix.latitude, myFix.longitude),
                radius: myFix.accuracy.clamp(8, 4000),
                useRadiusInMeter: true,
                color: Colors.blue.withOpacity(0.15),
              ),
            ]),
            MarkerLayer(markers: [
              Marker(
                point: LatLng(myFix.latitude, myFix.longitude),
                width: 22,
                height: 22,
                child: const Icon(Icons.circle,
                    size: 16, color: Color(0xFF2563EB)),
              ),
            ]),
          ],
          // hotspot markers
          MarkerLayer(markers: [
            for (final h in _hotspots)
              Marker(
                point: LatLng((h['lat'] as num).toDouble(),
                    (h['lon'] as num).toDouble()),
                width: 34,
                height: 34,
                child: GestureDetector(
                  onTap: () => _hotspotSheet(h),
                  child: Icon(
                    Icons.phishing_rounded,
                    size: 26,
                    color: h['caveat'] != null
                        ? OrcaTheme.warnAmber
                        : OrcaTheme.tealDeep,
                  ),
                ),
              ),
          ]),
        ],
      ),

      // ── top chips: layers / seamarks / fetch-here ──
      Positioned(
        top: 10,
        left: 12,
        right: 12,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _TopChip(
              icon: Icons.layers_rounded,
              label: _seaMarks ? '${'layers_lbl'.tr()}: OSM+${'sea_marks'.tr()}' : '${'layers_lbl'.tr()}: OSM',
              active: _seaMarks,
              onTap: () => setState(() => _seaMarks = !_seaMarks),
            ),
            const SizedBox(width: 8),
            _TopChip(
              icon: Icons.download_rounded,
              label: 'fetch_here'.tr(),
              onTap: _loading
                  ? null
                  : () {
                      final c = _ctrl.camera.center;
                      setState(() => _center = c);
                      _load(c);
                    },
            ),
          ]),
        ),
      ),

      if (_loading)
        const Positioned(
            top: 56,
            left: 0,
            right: 0,
            child: Center(
                child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.5)))),
      if (_err != null)
        Positioned(
            top: 56,
            left: 16,
            right: 16,
            child: FetchError(detail: _err!, onRetry: () => _load(_center))),

      // hint
      Positioned(
        bottom: 8,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: t.cardColor.withOpacity(0.9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.dividerColor)),
            child: Text('long_press_hint'.tr(),
                style: TextStyle(
                    fontSize: 10.5, color: t.colorScheme.secondary)),
          ),
        ),
      ),

      // hotspots bottom sheet (persistent)
      DraggableScrollableSheet(
        initialChildSize: 0.16,
        minChildSize: 0.12,
        maxChildSize: 0.55,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: t.scaffoldBackgroundColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: t.dividerColor),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.12), blurRadius: 14)
            ],
          ),
          child: ListView(controller: sc, padding: const EdgeInsets.all(14),
              children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                      color: t.dividerColor,
                      borderRadius: BorderRadius.circular(99))),
            ),
            Text('hotspots_title'.tr(),
                style: t.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (_hotspots.isEmpty && !_loading)
              Text('—', style: TextStyle(color: t.colorScheme.secondary)),
            for (final h in _hotspots) _hotspotRow(h),
          ]),
        ),
      ),
    ]);
  }

  Widget _hotspotRow(Map h) {
    final t = Theme.of(context);
    final hasCaveat = h['caveat'] != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: hasCaveat
                ? OrcaTheme.warnAmber.withOpacity(0.6)
                : t.dividerColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.location_on_rounded,
              size: 15,
              color: hasCaveat ? OrcaTheme.warnAmber : t.colorScheme.primary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              "${(h['lat'] as num).toStringAsFixed(2)}°N ${(h['lon'] as num).toStringAsFixed(2)}°E · chl ${(h['chl'] as num).toStringAsFixed(2)} mg/m³",
              style: t.textTheme.bodyMedium
                  ?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: 3),
        Text('${h['distance_nm']} NM ${h['bearing']}',
            style: t.textTheme.bodyMedium?.copyWith(
                fontSize: 11.5, color: t.colorScheme.secondary)),
        if (hasCaveat) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: OrcaTheme.alertBg,
                borderRadius: BorderRadius.circular(9)),
            child: Text('⚠ ${h['caveat']}',
                style: const TextStyle(
                    fontSize: 10.5, color: Color(0xFF92400E))),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: OrcaTheme.teal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11))),
            onPressed: () {
              widget.app.setTarget(NavTarget(
                  'chl ${(h['chl'] as num).toStringAsFixed(2)}',
                  (h['lat'] as num).toDouble(),
                  (h['lon'] as num).toDouble()));
              widget.app.jumpTab?.call(2);
            },
            icon: const Icon(Icons.explore_rounded,
                size: 17, color: Colors.white),
            label: Text('go_lbl'.tr(),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ]),
    );
  }

  void _hotspotSheet(Map h) {
    final t = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: _hotspotRow(h),
      ),
    );
  }

  /// Long-press → nearest met cell reading (bottom card, honest land flag).
  void _inspectPoint(LatLng ll) {
    final pts = _metPoints;
    if (pts.isEmpty) return;
    Map best = pts.first;
    var bestD = double.infinity;
    for (final p in pts) {
      final d = Marine.haversineKm(ll.latitude, ll.longitude,
          (p['lat'] as num).toDouble(), (p['lon'] as num).toDouble());
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    final t = Theme.of(context);
    String v(String k, String u, [int dp = 1]) => best[k] is num
        ? '${(best[k] as num).toStringAsFixed(dp)} $u'
        : '—';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (best['land'] == true)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9)),
              child: Text('⚠ ${'land_cell'.tr()} (GLOBE)',
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _mini('waves_lbl'.tr(), v('wave_m', 'm')),
            _mini('wind_lbl'.tr(), v('wind_kn', 'kn', 0)),
            _mini('sst_lbl'.tr(), v('sst_c', '°C')),
            _mini('current_lbl'.tr(), v('current_kn', 'kn', 2)),
          ]),
        ]),
      ),
    );
  }

  Widget _mini(String l, String v) => Column(children: [
        Text(l, style: const TextStyle(fontSize: 10.5)),
        const SizedBox(height: 3),
        Text(v,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ]);
}

class _TopChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  const _TopChip(
      {required this.icon,
      required this.label,
      this.active = false,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? t.colorScheme.primary : t.cardColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.dividerColor),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 15,
              color: active ? Colors.white : t.colorScheme.secondary),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : t.colorScheme.onSurface)),
        ]),
      ),
    );
  }
}
