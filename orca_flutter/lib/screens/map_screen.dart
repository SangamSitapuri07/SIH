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
  final double _zoom = 9.5;

  // (B2) tap-probe + search
  LatLng? _tap;
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchRes = const [];
  bool _searchBusy = false, _searchedOnce = false;
  String? _searchErr;

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
          onTap: (_, ll) => _probe(ll),
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
          // (B2) tap dot — user ne KAHAN tap kiya (probe point)
          if (_tap != null)
            MarkerLayer(markers: [
              Marker(
                point: _tap!,
                width: 26,
                height: 26,
                child: Container(
                  decoration: BoxDecoration(
                    color: OrcaTheme.teal,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                          color: OrcaTheme.tealDeep.withOpacity(0.45),
                          blurRadius: 8)
                    ],
                  ),
                ),
              ),
            ]),
        ],
      ),

      // ── top: SEARCH bar + chips ──
      Positioned(
        top: 10,
        left: 12,
        right: 12,
        child: Column(children: [
          _searchBar(context),
          const SizedBox(height: 8),
          SingleChildScrollView(
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
        ]),
      ),

      if (_loading)
        const Positioned(
            top: 116,
            left: 0,
            right: 0,
            child: Center(
                child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.5)))),
      if (_err != null)
        Positioned(
            top: 116,
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
            child: Text('map_tap_hint'.tr(),
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
        // (B10) "Go" button hidden — Navigate tab web pe test ho raha hai
      ]),
    );
  }

  void _hotspotSheet(Map h) {
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

  // ── (B2) tap → dot + data sheet (kahan tap kiya, kahan ka data) ──
  void _probe(LatLng ll) {
    widget.app.setProbe(ll);
    setState(() => _tap = ll);
    Map? best;
    double? bestD;
    for (final p in _metPoints) {
      final d = Marine.haversineKm(ll.latitude, ll.longitude,
          (p['lat'] as num).toDouble(), (p['lon'] as num).toDouble());
      if (bestD == null || d < bestD) {
        bestD = d;
        best = p;
      }
    }
    String v(Map m, String k, String u, [int dp = 1]) =>
        m[k] is num ? '${(m[k] as num).toStringAsFixed(dp)} $u' : '—';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '📍 ${ll.latitude.toStringAsFixed(3)}°N ${ll.longitude.toStringAsFixed(3)}°E',
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 4),
          if (best == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('fetch_here'.tr(),
                  style: Theme.of(ctx).textTheme.bodySmall),
            )
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'map_probe_from'.tr(args: [(bestD ?? 0).toStringAsFixed(1)]),
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(ctx).colorScheme.secondary),
              ),
            ),
            if (best['land'] == true)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(9)),
                child: Text('⚠ ${'land_cell'.tr()} (GLOBE)',
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _mini('waves_lbl'.tr(), v(best, 'wave_m', 'm')),
              _mini('wind_lbl'.tr(), v(best, 'wind_kn', 'kn', 0)),
              _mini('sst_lbl'.tr(), v(best, 'sst_c', '°C')),
              _mini('current_lbl'.tr(), v(best, 'current_kn', 'kn', 2)),
            ]),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _center = ll);
                  _load(ll);
                },
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text('fetch_here'.tr()),
              ),
            ),
            // (B10) "Navigate here" hidden — Navigate tab abhi web lab mein
          ]),
        ]),
      ),
    );
  }

  // ── (B2) search: OSM Nominatim (real geocoder) ──
  Future<void> _search(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    setState(() {
      _searchBusy = true;
      _searchErr = null;
      _searchRes = const [];
      _searchedOnce = true;
    });
    try {
      final r = await OrcaApi.geocode(q);
      if (!mounted) return;
      setState(() {
        _searchRes = r;
        _searchBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchErr = '$e';
        _searchBusy = false;
      });
    }
  }

  void _goResult(Map<String, dynamic> r) {
    final lat = double.tryParse('${r['lat']}');
    final lon = double.tryParse('${r['lon']}');
    if (lat == null || lon == null) return;
    final ll = LatLng(lat, lon);
    setState(() => _searchRes = const []);
    _searchCtrl.clear();
    _ctrl.move(ll, 11);
    _probe(ll);
  }

  Widget _searchBar(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.dividerColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)
        ],
      ),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 10),
          Icon(Icons.search_rounded,
              size: 18, color: t.colorScheme.secondary),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'map_search_hint'.tr(),
                isDense: true,
              ),
            ),
          ),
          _searchBusy
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  onPressed: () => _search(_searchCtrl.text),
                  visualDensity: VisualDensity.compact,
                ),
        ]),
        if (_searchErr != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('✖ $_searchErr',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, color: OrcaTheme.dangerRed)),
            ),
          )
        else if (_searchRes.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _searchRes.length,
              itemBuilder: (_, i) {
                final r = _searchRes[i];
                final name = '${r['display_name'] ?? ''}';
                final short = name.split(',').first;
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, size: 18),
                  title: Text(short,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  subtitle: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10)),
                  onTap: () => _goResult(r),
                );
              },
            ),
          )
        else if (_searchedOnce && !_searchBusy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('search_no_result'.tr(),
                style: TextStyle(
                    fontSize: 11, color: t.colorScheme.secondary)),
          ),
      ]),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
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
