import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../marine.dart';
import '../theme.dart';

/// (B8) ROUTE ANALYSIS — "faisla aaya kahan se?" ki poori kitaab.
///
/// Judges / skipper dono ke liye: bada map (legs + har sample point ka
/// colored marker), verdict ka fold logic, HAR point ke OBSERVED numbers
/// (wave/wind/gust/current/SST + why-evidence), decision rules table,
/// land verification method, sources. Koi adjective nahi — sirf numbers
/// aur unke rules. Sab data backend route-advisory/route-check ka REAL
/// response hai; fail hua point honestly 'unknown' dikhta hai.
class RouteAnalysisScreen extends StatelessWidget {
  /// route-check result ya route-advisory se bana hua map (legs, distance…)
  final Map<String, dynamic> route;

  /// transit verdict — null ho to sirf geometry/rules dikhte hain
  final Map<String, dynamic>? rt;
  final Object? rtErr;
  final String startName;
  final String destName;

  const RouteAnalysisScreen({
    super.key,
    required this.route,
    required this.rt,
    required this.rtErr,
    required this.startName,
    required this.destName,
  });

  static double _lat(dynamic l) =>
      l is List ? (l[0] as num).toDouble() : (l['lat'] as num).toDouble();
  static double _lon(dynamic l) =>
      l is List ? (l[1] as num).toDouble() : (l['lon'] as num).toDouble();

  Color _stateColor(String s) => s == 'good'
      ? OrcaTheme.okGreen
      : s == 'danger'
          ? OrcaTheme.dangerRed
          : s == 'caution'
              ? OrcaTheme.warnAmber
              : Colors.grey;

  String _fmt(dynamic x, String u, [int dp = 1]) =>
      x is num ? '${x.toStringAsFixed(dp)}$u' : '—';

  // ── (B16 P2) mockup-5 widgets ────────────────────────────────────
  Widget _verdictRow(ThemeData t, String lvl, String emoji, String key,
      Color c, String active) {
    final on = active == lvl;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: on ? c.withOpacity(0.16) : c.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: c.withOpacity(on ? 0.85 : 0.22), width: on ? 1.6 : 1),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(key.tr(),
              style: t.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: on ? c : c.withOpacity(0.45))),
        ),
        if (on)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration:
                BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
            child: Text('ra_active'.tr(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8)),
          ),
      ]),
    );
  }

  Widget _chip(ThemeData t, String txt, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: c.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.withOpacity(0.4))),
        child: Text(txt,
            style: t.textTheme.bodySmall?.copyWith(
                color: c, fontWeight: FontWeight.w800, fontSize: 11)),
      );

  int _findState(List pts, String want) {
    for (var i = 0; i < pts.length; i++) {
      if ('${pts[i]['state']}' == want) return i;
    }
    return -1;
  }

  Widget _kyunLine(ThemeData t, List pts) {
    // (B12) worst-point kyun — pehla danger > caution > unknown > all-clear
    final di = _findState(pts, 'danger');
    final ci = _findState(pts, 'caution');
    final ui = _findState(pts, 'unknown');
    String txt;
    Color col;
    if (di >= 0 || ci >= 0) {
      final i = di >= 0 ? di : ci;
      final why = pts[i]['why'];
      txt =
          "🎯 ${'ra_kyun'.tr()}: ${'ra_point_word'.tr()} ${i + 1} — ${why ?? 'ra_why_generic'.tr()}";
      col = di >= 0 ? OrcaTheme.dangerRed : OrcaTheme.warnAmber;
    } else if (ui >= 0) {
      txt = "🎯 ${'ra_kyun'.tr()}: ${'ra_why_unknown'.tr()}";
      col = OrcaTheme.warnAmber;
    } else {
      txt = "🎯 ${'ra_kyun'.tr()}: ${'ra_allclear'.tr()}";
      col = OrcaTheme.okGreen;
    }
    return Text(txt,
        style: t.textTheme.bodySmall?.copyWith(
            color: col, fontWeight: FontWeight.w700, fontSize: 11.5));
  }

  Widget _nmChips(ThemeData t) {
    final rerouted = rt?['rerouted'] == true;
    final direct = rt?['straight_distance_nm'];
    final routed = route['distance_nm'] ?? rt?['distance_nm'];
    return Wrap(spacing: 8, runSpacing: 6, children: [
      _chip(
          t,
          direct is num
              ? '📏 ${direct.toStringAsFixed(1)} NM · ${'ra_direct'.tr()}'
              : '${_fmt(route['distance_nm'] ?? rt?['distance_nm'], ' NM')} · ${'ra_direct'.tr()}',
          t.colorScheme.secondary),
      if (rerouted && routed is num)
        _chip(t, '🌊 ${routed.toStringAsFixed(1)} NM · ${'ra_routed'.tr()}',
            const Color(0xFF38BDF8)),
    ]);
  }

  Widget _rerouteBanner(ThemeData t) {
    final wps = (rt?['waypoints'] as List?) ?? const [];
    const cyan = Color(0xFF38BDF8);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: cyan.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cyan.withOpacity(0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ra_reroute_t'.tr(),
            style: t.textTheme.bodySmall?.copyWith(
                color: cyan, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
        const SizedBox(height: 4),
        Text('ra_reroute'.tr(args: ['${wps.length}']),
            style: t.textTheme.bodySmall?.copyWith(
                color: cyan, fontSize: 11, height: 1.45)),
      ]),
    );
  }


  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final legsRaw = ((route['legs'] as List?) ?? const []);
    final legs = [for (final l in legsRaw) LatLng(_lat(l), _lon(l))];
    final pts = ((rt?['points'] as List?) ?? const []);
    final v = (rt?['verdict'] as Map?) ?? const {};
    final level = '${v['level']}';
    final lvlColor = level == 'go'
        ? OrcaTheme.okGreen
        : level == 'nogo'
            ? OrcaTheme.dangerRed
            : level == 'caution'
                ? OrcaTheme.warnAmber
                : Colors.grey;
    final lvlKey = level == 'go'
        ? 'rt_go'
        : level == 'nogo'
            ? 'rt_nogo'
            : level == 'caution'
                ? 'rt_caution'
                : 'rt_unknown';

    return Scaffold(
      appBar: AppBar(title: Text('ra_title'.tr())),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        // ── route map: legs + sample-point markers (numbers+sail km) ──
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 300,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: legs.length >= 2
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(legs),
                        padding: const EdgeInsets.all(28))
                    : null,
                initialCenter:
                    legs.isNotEmpty ? legs.first : const LatLng(18, 70),
                initialZoom: 7,
              ),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'in.sih2026.orca'),
                if (legs.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(
                        points: legs,
                        strokeWidth: 3.5,
                        color: OrcaTheme.teal),
                  ]),
                MarkerLayer(markers: [
                  // start / dest flags
                  if (legs.isNotEmpty)
                    Marker(
                        point: legs.first,
                        width: 26,
                        height: 26,
                        child: const Icon(Icons.play_arrow_rounded,
                            color: OrcaTheme.okGreen, size: 26)),
                  if (legs.length >= 2)
                    Marker(
                        point: legs.last,
                        width: 26,
                        height: 26,
                        child: const Icon(Icons.flag_rounded,
                            color: OrcaTheme.dangerRed, size: 24)),
                  // (B11) seapath waypoints — chhote cyan dots (reroute bends)
                  for (final w in ((rt?['waypoints'] as List?) ?? const []))
                    Marker(
                      point: LatLng(_lat(w), _lon(w)),
                      width: 8,
                      height: 8,
                      child: Container(
                        decoration: const BoxDecoration(
                            color: Color(0xFF38BDF8), shape: BoxShape.circle),
                      ),
                    ),
                  // analysis sample points — state-colored numbered dots
                  for (var i = 0; i < pts.length; i++)
                    Marker(
                      point: LatLng((pts[i]['lat'] as num).toDouble(),
                          (pts[i]['lon'] as num).toDouble()),
                      width: 44,
                      height: 30,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: _stateColor('${pts[i]['state']}'),
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 1.5)),
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900)),
                        ),
                        Text(
                            Marine.kmToNm((pts[i]['sail_km'] as num? ?? 0)
                                    .toDouble())
                                .toStringAsFixed(0),
                            style: const TextStyle(
                                fontSize: 8,
                                color: Colors.white,
                                shadows: [
                                  Shadow(blurRadius: 2, color: Colors.black)
                                ])),
                      ]),
                    ),
                ]),
              ],
            ),
          ),
        ),
        if (legs.length >= 2) ...[
          const SizedBox(height: 6),
          Center(
            child: Text(
              '📏 ${_fmt(route['distance_km'] ?? rt?['distance_km'], ' km')} · '
              '${_fmt(route['distance_nm'] ?? rt?['distance_nm'], ' NM')} · '
              '🧭 ${_fmt(route['bearing_deg'] ?? rt?['bearing_deg'], '°')}\n'
              '$startName → $destName',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.secondary),
            ),
          ),
        ],

        // ── verdict banner / failure ──
        const SizedBox(height: 12),
        if (rt != null) ...[
          _verdictRow(t, 'go', '✅', 'rt_go', OrcaTheme.okGreen, level),
          const SizedBox(height: 6),
          _verdictRow(
              t, 'caution', '⚠️', 'rt_caution', OrcaTheme.warnAmber, level),
          const SizedBox(height: 6),
          _verdictRow(t, 'nogo', '⛔', 'rt_nogo', OrcaTheme.dangerRed, level),
          if (level == 'unknown') ...[
            const SizedBox(height: 6),
            _verdictRow(t, 'unknown', '⚪', 'rt_unknown', Colors.grey, level),
          ],
          const SizedBox(height: 4),
          Text(
            'rt_pts'.tr(args: [
              '${v['points_known'] ?? 0}',
              '${v['points_total'] ?? 0}'
            ]),
            style: t.textTheme.bodySmall
                ?.copyWith(color: t.colorScheme.secondary),
          ),
          if ((rt?['safe_window_at_start'] as Map?)?['found'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                "⏱ ${'rt_window'.tr()}: ${rt?['safe_window_at_start']['note'] ?? ''}",
                style: t.textTheme.bodySmall
                    ?.copyWith(color: OrcaTheme.okGreen, fontSize: 11),
              ),
            ),
          const SizedBox(height: 10),
          _kyunLine(t, pts),
          const SizedBox(height: 8),
          _nmChips(t),
          if (rt?['rerouted'] == true) ...[
            const SizedBox(height: 8),
            _rerouteBanner(t),
          ],
        ]
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: OrcaTheme.dangerRed.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: OrcaTheme.dangerRed.withOpacity(0.6))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('rt_failed'.tr(),
                  style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800, color: OrcaTheme.dangerRed)),
              if (rtErr != null)
                Text('$rtErr',
                    style: t.textTheme.bodySmall?.copyWith(
                        fontSize: 10, color: t.colorScheme.secondary)),
            ]),
          ),

        // ── decision rules — KAUNSI value se faisla ──
        const SizedBox(height: 14),
        _secTitle(t, Icons.rule_rounded, 'ra_rules'),
        Card(
          margin: const EdgeInsets.only(top: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ra_rule_wave'.tr(), style: t.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text('ra_rule_wind'.tr(), style: t.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text('ra_rule_current'.tr(), style: t.textTheme.bodySmall),
              Divider(height: 14, color: t.dividerColor),
              Text('ra_rule_worst'.tr(),
                  style: t.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),

        // ── land verification ──
        const SizedBox(height: 14),
        _secTitle(t, Icons.terrain_rounded, 'ra_land'),
        Card(
          margin: const EdgeInsets.only(top: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(
                    route['ok'] == true || rt?['land_ok'] == true
                        ? Icons.check_circle_rounded
                        : (route['ok'] == false || rt?['land_ok'] == false)
                            ? Icons.cancel_rounded
                            : Icons.help_rounded,
                    size: 18,
                    color: (route['ok'] == true || rt?['land_ok'] == true)
                        ? OrcaTheme.okGreen
                        : (route['ok'] == false || rt?['land_ok'] == false)
                            ? OrcaTheme.dangerRed
                            : OrcaTheme.warnAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (route['ok'] == false || rt?['land_ok'] == false)
                        ? 'rt_land_blocked'.tr()
                        : (route['detour'] == true || rt?['detour'] == true)
                            ? 'rt_land_detour'.tr()
                            : ((route['ok'] == null && rt?['land_ok'] == null)
                                ? 'rt_land_unverified'.tr()
                                : 'ra_land_clear'.tr()),
                    style: t.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                  '${route['reason'] ?? rt?['land_reason'] ?? ''}'
                  '${rt?['method'] != null ? '\n${rt?['method']}' : ''}'
                  '${rt?['sample_spacing_km'] != null ? '\nSample spacing: ${rt?['sample_spacing_km']} km' : ''}',
                  style: t.textTheme.bodySmall?.copyWith(
                      fontSize: 10.5, color: t.colorScheme.secondary)),
            ]),
          ),
        ),

        // ── har point ka FULL data — evidence cards ──
        if (pts.isNotEmpty) ...[
          const SizedBox(height: 14),
          _secTitle(t, Icons.pin_drop_rounded, 'ra_points'),
          for (var i = 0; i < pts.length; i++)
            Card(
              margin: const EdgeInsets.only(top: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: _stateColor('${pts[i]['state']}').withOpacity(0.5))),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.circle,
                            size: 11, color: _stateColor('${pts[i]['state']}')),
                        const SizedBox(width: 6),
                        Text(
                            "${'ra_pt_lbl'.tr()} ${i + 1} · ${Marine.kmToNm((pts[i]['sail_km'] as num? ?? 0).toDouble()).toStringAsFixed(0)} NM",
                            style: t.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        Text('${pts[i]['lat']}, ${pts[i]['lon']}',
                            style: t.textTheme.bodySmall?.copyWith(
                                fontSize: 10, color: t.colorScheme.secondary)),
                      ]),
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, runSpacing: 4, children: [
                        Text('🌊 ${_fmt(pts[i]['wave_m'], ' m')}',
                            style: t.textTheme.bodySmall),
                        Text('↗48h: ${_fmt(pts[i]['wave_48h_max_m'], ' m')}',
                            style: t.textTheme.bodySmall
                                ?.copyWith(color: t.colorScheme.secondary)),
                        Text('💨 ${_fmt(pts[i]['wind_kn'], ' kn', 0)}',
                            style: t.textTheme.bodySmall),
                        Text('↗48h: ${_fmt(pts[i]['wind_48h_max_kn'], ' kn', 0)}',
                            style: t.textTheme.bodySmall
                                ?.copyWith(color: t.colorScheme.secondary)),
                        Text('🌀 gust48: ${_fmt(pts[i]['gust_48h_max_kn'], ' kn', 0)}',
                            style: t.textTheme.bodySmall
                                ?.copyWith(color: t.colorScheme.secondary)),
                        Text('⟲ ${_fmt(pts[i]['current_kn'], ' kn')}',
                            style: t.textTheme.bodySmall),
                        Text('🌡 ${_fmt(pts[i]['sst_c'], '°')}',
                            style: t.textTheme.bodySmall),
                      ]),
                      if (pts[i]['why'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('⚠ ${pts[i]['why']}',
                              style: t.textTheme.bodySmall?.copyWith(
                                  color: ('${pts[i]['state']}' == 'danger')
                                      ? OrcaTheme.dangerRed
                                      : OrcaTheme.warnAmber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      if (pts[i]['note'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('ℹ ${pts[i]['note']}',
                              style: t.textTheme.bodySmall?.copyWith(
                                  color: t.colorScheme.secondary, fontSize: 11)),
                        ),
                    ]),
              ),
            ),
        ],

        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('ra_honest_footer'.tr(),
              style: t.textTheme.bodySmall?.copyWith(
                  fontSize: 9.5,
                  color: t.colorScheme.secondary,
                  height: 1.4)),
        ),

        // ── sources honesty ──
        if (rt != null) ...[
          const SizedBox(height: 14),
          _secTitle(t, Icons.satellite_alt_rounded, 'ra_data'),
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in ((rt?['sources_used'] as List?) ?? const []))
                      Text('✔ $s',
                          style: t.textTheme.bodySmall?.copyWith(
                              fontSize: 11, color: OrcaTheme.okGreen)),
                    for (final s
                        in ((rt?['sources_failed'] as List?) ?? const []))
                      Text('✘ $s',
                          style: t.textTheme.bodySmall?.copyWith(
                              fontSize: 11, color: OrcaTheme.dangerRed)),
                    if (rt?['fetched_at'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('ai_fetched'.tr(args: ['${rt?['fetched_at']}']),
                            style: t.textTheme.bodySmall?.copyWith(
                                fontSize: 10, color: t.colorScheme.secondary)),
                      ),
                  ]),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _secTitle(ThemeData t, IconData ic, String key) => Row(children: [
        Icon(ic, size: 17, color: t.colorScheme.secondary),
        const SizedBox(width: 6),
        Text(key.tr(),
            style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      ]);
}
