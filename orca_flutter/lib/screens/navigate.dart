import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api.dart';
import '../marine.dart';
import '../state.dart';
import '../theme.dart';
import 'home.dart' show orcaFix;

final _notif = FlutterLocalNotificationsPlugin();
bool _notifReady = false;

Future<void> _notifyArrival(String body) async {
  try {
    if (!_notifReady) {
      await _notif.initialize(const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _notifReady = true;
    }
    await _notif.show(
        7,
        'ORCA 🐟',
        body,
        const NotificationDetails(
            android: AndroidNotificationDetails('orca_nav', 'Navigation',
                importance: Importance.high, priority: Priority.high)));
  } catch (_) {}
}

class NavigateScreen extends StatefulWidget {
  final Settings settings;
  final AppState app;
  const NavigateScreen({super.key, required this.settings, required this.app});

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen>
    with WidgetsBindingObserver {
  static const _arriveNm = 0.3, _offCourseNm = 0.5, _jitterM = 20.0, _maxPts = 3000;

  StreamSubscription<Position>? _posSub;
  Position? _fix;
  List<LatLng> _trace = [];
  Map<String, dynamic>? _route;
  NavTarget? _routeFor; // route-check kis target ke liye chala
  bool _wakeOn = false, _arrivedNotified = false;
  String? _gpsErr;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreTrace();
    widget.app.addListener(_onTarget);
    _start();
  }

  void _onTarget() {
    // naya target → route-check zaaroori (ek baar per target)
    if (widget.app.navTarget != _routeFor) {
      _route = null;
      _arrivedNotified = false;
      _maybeRouteCheck();
    }
    if (mounted) setState(() {});
  }

  Future<void> _restoreTrace() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('orca_trace');
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()))
            .toList();
        if (mounted) setState(() => _trace = list);
      } catch (_) {}
    }
  }

  Future<void> _saveTrace() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'orca_trace',
        jsonEncode(
            _trace.map((e) => [e.latitude, e.longitude]).toList()));
  }

  Future<void> _start() async {
    try {
      final fix = await orcaFix();
      _applyFix(fix);
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best, distanceFilter: 10),
      ).listen(_applyFix, onError: (e) {
        if (mounted) setState(() => _gpsErr = '$e');
      });
      if (mounted) setState(() => _gpsErr = null);
    } on StateError catch (e) {
      if (mounted) setState(() => _gpsErr = e.message);
    } catch (e) {
      if (mounted) setState(() => _gpsErr = '$e');
    }
  }

  void _applyFix(Position fix) {
    if (!mounted) return;
    widget.app.setFix(fix);
    _fix = fix;
    // breadcrumb (20m jitter filter, 3000 cap)
    if (_trace.isEmpty ||
        Marine.haversineKm(_trace.last.latitude, _trace.last.longitude,
                fix.latitude, fix.longitude) *
            1000 >
            _jitterM) {
      _trace.add(LatLng(fix.latitude, fix.longitude));
      if (_trace.length > _maxPts) _trace.removeAt(0);
      if (_trace.length % 5 == 0) _saveTrace();
    }
    _maybeRouteCheck();
    _checkArrival(fix);
    // wakelock: target hai to screen on rakho
    final wantWake = widget.app.navTarget != null;
    if (wantWake != _wakeOn) {
      _wakeOn = wantWake;
      wantWake ? WakelockPlus.enable() : WakelockPlus.disable();
    }
    setState(() {});
  }

  Future<void> _maybeRouteCheck() async {
    final tgt = widget.app.navTarget;
    final fix = _fix;
    if (tgt == null || fix == null) return;
    if (_routeFor == tgt && _route != null) return;
    _routeFor = tgt;
    try {
      final r = await OrcaApi.routeCheck(
          widget.settings.base, fix.latitude, fix.longitude, tgt.lat, tgt.lon);
      if (mounted && widget.app.navTarget == tgt) {
        setState(() => _route = r);
      }
    } catch (e) {
      if (mounted && widget.app.navTarget == tgt) {
        setState(() => _route = {
              'ok': null,
              'reason': 'route-check failed: $e',
              'legs': [
                {'lat': fix.latitude, 'lon': fix.longitude},
                {'lat': tgt.lat, 'lon': tgt.lon},
              ],
            });
      }
    }
  }

  void _checkArrival(Position fix) {
    final tgt = widget.app.navTarget;
    if (tgt == null) return;
    final dNm = Marine.kmToNm(
        Marine.haversineKm(fix.latitude, fix.longitude, tgt.lat, tgt.lon));
    if (dNm <= _arriveNm && !_arrivedNotified) {
      _arrivedNotified = true;
      _notifyArrival('${tgt.name} — ${dNm.toStringAsFixed(1)} NM');
    } else if (dNm > _arriveNm * 2) {
      _arrivedNotified = false; // reset jab phir door jao
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    widget.app.removeListener(_onTarget);
    if (_wakeOn) WakelockPlus.disable();
    _saveTrace();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tgt = widget.app.navTarget;
    if (tgt == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.explore_off_rounded,
                size: 46, color: t.colorScheme.secondary.withOpacity(0.7)),
            const SizedBox(height: 12),
            Text('nav_no_target'.tr(),
                textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: OrcaTheme.teal),
              onPressed: () => widget.app.jumpTab?.call(1),
              icon: const Icon(Icons.map_rounded,
                  size: 18, color: Colors.white),
              label: Text('pick_on_map'.tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ]),
        ),
      );
    }

    final fix = _fix;
    final distNm = fix == null
        ? null
        : Marine.kmToNm(Marine.haversineKm(
            fix.latitude, fix.longitude, tgt.lat, tgt.lon));
    final brg = fix == null
        ? null
        : Marine.bearingDeg(fix.latitude, fix.longitude, tgt.lat, tgt.lon);
    final speedKn = fix == null ? 0.0 : fix.speed * 1.943844;
    // cross-track vs best leg
    double? xtrackNm;
    final legs = (_route?['legs'] as List?) ?? [];
    if (fix != null && legs.length >= 2) {
      var best = double.infinity;
      for (var i = 0; i + 1 < legs.length; i++) {
        final a = legs[i], b = legs[i + 1];
        final d = Marine.crossTrackKm(
            fix.latitude,
            fix.longitude,
            (a['lat'] as num).toDouble(),
            (a['lon'] as num).toDouble(),
            (b['lat'] as num).toDouble(),
            (b['lon'] as num).toDouble());
        if (d < best) best = d;
      }
      if (best.isFinite) xtrackNm = Marine.kmToNm(best);
    }
    final offCourse = xtrackNm != null && xtrackNm > _offCourseNm;
    final arrived = distNm != null && distNm <= _arriveNm;
    final steer = (fix != null && speedKn > 1.0 && brg != null)
        ? Marine.steerHint(fix.heading, brg)
        : null;
    final String? steerTxt = steer == null
        ? null
        : (steer.left
            ? 'steer_left'.tr(args: ['${steer.deg.toInt()}'])
            : 'steer_right'.tr(args: ['${steer.deg.toInt()}']));

    return Column(children: [
      // ── status strip: verified / blocked / unverified / arrival / off-course ──
      _StatusBanner(
          route: _route,
          arrived: arrived,
          offCourse: offCourse,
          steerTxt: steerTxt),
      // ── mini map ──
      SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: fix != null
                ? LatLng(fix.latitude, fix.longitude)
                : LatLng(tgt.lat, tgt.lon),
            initialZoom: 10.5,
          ),
          children: [
            TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'in.sih2026.orca'),
            PolylineLayer(polylines: [
              if (_trace.length > 1)
                Polyline(
                    points: _trace,
                    strokeWidth: 3,
                    color: const Color(0xFFF97316)),
              if (legs.length >= 2)
                Polyline(
                  points: [
                    for (final l in legs)
                      LatLng((l['lat'] as num).toDouble(),
                          (l['lon'] as num).toDouble())
                  ],
                  strokeWidth: 3.5,
                  color: _route?['ok'] == true
                      ? OrcaTheme.teal
                      : _route?['ok'] == false
                          ? OrcaTheme.dangerRed
                          : OrcaTheme.warnAmber,
                ),
            ]),
            if (fix != null)
              MarkerLayer(markers: [
                Marker(
                    point: LatLng(fix.latitude, fix.longitude),
                    width: 20,
                    height: 20,
                    child: const Icon(Icons.circle,
                        size: 14, color: Color(0xFF2563EB))),
              ]),
            MarkerLayer(markers: [
              Marker(
                  point: LatLng(tgt.lat, tgt.lon),
                  width: 30,
                  height: 30,
                  child: const Icon(Icons.phishing_rounded,
                      size: 24, color: OrcaTheme.tealDeep)),
            ]),
          ],
        ),
      ),
      // ── target card + clear ──
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Row(children: [
          Expanded(
            child: Text(
                '🎯 ${tgt.lat.toStringAsFixed(3)}°N ${tgt.lon.toStringAsFixed(3)}°E · ${tgt.name}',
                style: t.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700, fontSize: 12.5),
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
              onPressed: () {
                widget.app.clearTarget();
                _route = null;
                _routeFor = null;
                if (_wakeOn) WakelockPlus.disable();
                _wakeOn = false;
                setState(() {});
              },
              icon: Icon(Icons.close_rounded,
                  size: 20, color: t.colorScheme.secondary)),
        ]),
      ),
      // ── HUD ──
      Expanded(
        child: _gpsErr != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_gpsErr!.tr(),
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium
                          ?.copyWith(color: OrcaTheme.dangerRed)),
                ),
              )
            : GridView.count(
                crossAxisCount: 3,
                padding: const EdgeInsets.all(12),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.15,
                children: [
                  _Hud(
                      'distance_lbl'.tr(),
                      distNm == null ? '—' : '${distNm.toStringAsFixed(1)} NM',
                      OrcaTheme.teal),
                  _Hud(
                      'bearing_lbl'.tr(),
                      brg == null
                          ? '—'
                          : '${brg.toStringAsFixed(0).padLeft(3, '0')}° ${Marine.compass16(brg)}',
                      OrcaTheme.tealDeep),
                  _Hud(
                      'eta_lbl'.tr(),
                      distNm == null
                          ? '—'
                          : Marine.eta(
                              Marine.haversineKm(
                                  fix!.latitude, fix!.longitude, tgt.lat, tgt.lon),
                              speedKn),
                      OrcaTheme.okGreen),
                  _Hud('speed_lbl'.tr(), '${speedKn.toStringAsFixed(1)} kn',
                      OrcaTheme.warnAmber),
                  _Hud(
                      'xtrack_lbl'.tr(),
                      xtrackNm == null
                          ? '—'
                          : '${xtrackNm.toStringAsFixed(2)} NM ${offCourse ? '⚠' : '✓'}',
                      offCourse ? OrcaTheme.dangerRed : OrcaTheme.okGreen),
                  _Hud(
                      '🧭',
                      steerTxt ?? (arrived ? '🐟' : '—'),
                      OrcaTheme.warnAmber,
                      small: true),
                ],
              ),
      ),
      // ── trace button + SOS shortcut ──
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _trace = _trace.isEmpty
                      ? (fix != null
                          ? [LatLng(fix.latitude, fix.longitude)]
                          : [])
                      : [];
                });
              },
              icon: const Icon(Icons.timeline_rounded, size: 17),
              label: Text('trace_lbl'.tr()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: OrcaTheme.dangerRed),
              onPressed: () => widget.app.jumpTab?.call(3),
              icon: const Icon(Icons.sos_rounded,
                  size: 18, color: Colors.white),
              label: const Text('SOS',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _StatusBanner extends StatelessWidget {
  final Map<String, dynamic>? route;
  final bool arrived, offCourse;
  final String? steerTxt;
  const _StatusBanner(
      {this.route,
      required this.arrived,
      required this.offCourse,
      this.steerTxt});

  @override
  Widget build(BuildContext context) {
    if (arrived) {
      return _banner(OrcaTheme.okGreen, 'arrived_msg'.tr());
    }
    if (offCourse && steerTxt != null) {
      return _banner(OrcaTheme.warnAmber,
          "${'offcourse_msg'.tr()} — $steerTxt");
    }
    final ok = route?['ok'];
    if (ok == true) {
      return _banner(OrcaTheme.okGreen,
          '${'sea_ok_msg'.tr()}${route?['detour'] == true ? ' (detour)' : ''}');
    }
    if (ok == false) {
      return _banner(OrcaTheme.dangerRed, 'blocked_msg'.tr());
    }
    if (route != null) {
      return _banner(OrcaTheme.warnAmber, 'unverified_msg'.tr());
    }
    return const SizedBox(height: 6);
  }

  Widget _banner(Color c, String msg) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.withOpacity(0.55))),
        child: Text(msg,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: c)),
      );
}

class _Hud extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool small;
  const _Hud(this.label, this.value, this.color, {this.small = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
          color: t.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.dividerColor)),
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: t.textTheme.bodyMedium
                ?.copyWith(fontSize: 10, color: t.colorScheme.secondary)),
        const Spacer(),
        Text(value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.titleLarge?.copyWith(
                fontSize: small ? 12.5 : 15, color: color)),
      ]),
    );
  }
}
