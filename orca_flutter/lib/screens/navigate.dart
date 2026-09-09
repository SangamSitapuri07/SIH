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
import '../data/harbours.dart';
import '../marine.dart';
import '../state.dart';
import '../theme.dart';
import 'home.dart' show orcaFix;
import 'route_analysis.dart';

final _notif = FlutterLocalNotificationsPlugin();
bool _notifReady = false;

Future<void> _notifyArrival(String body, [int id = 7]) async {
  try {
    if (!_notifReady) {
      await _notif.initialize(const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _notifReady = true;
    }
    await _notif.show(
        id,
        'ORCA ⚠️',
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
    // naya target → route-check + destination advisory (ek baar per target)
    if (widget.app.navTarget != _routeFor) {
      _route = null;
      _arrivedNotified = false;
      _maybeRouteCheck();
      _rtAdv = null;
      _rtAdvFor = null;
      _rtAdvErr = null;
      _rules = null; // (B5)
      _bannerTxt = null;
      _tgtColorRank = 1;
    }
    if (widget.app.navTarget == null) {
      _tgtAdv = null;
      _tgtAdvFor = null;
      _tgtAdvErr = null;
      _rtAdv = null;
      _rtAdvFor = null;
      _rtAdvErr = null;
      _rules = null;
      _bannerTxt = null;
      _wxTimer?.cancel();
    } else {
      _maybeTgtAdv();
      _maybeRtAdv(); // (B6) target set + manual start — bina GPS bhi verdict
      _startWxWatcher(); // (B5) destination badli to alert
    }
    if (mounted) setState(() {});
  }

  // ── (B4) TRANSIT VERDICT — poore raste ka GO/CAUTION/NO-GO ──
  Map<String, dynamic>? _rtAdv;
  Object? _rtAdvErr;
  Object? _rtAdvFor;

  // ── (B5) LIVE ALERTS — offline NavRules + destination watcher ──
  NavRules? _rules;
  String? _bannerTxt;
  Color? _bannerCol;
  DateTime? _bannerAt;
  Timer? _wxTimer;
  int _tgtColorRank = 1; // destination advisory ka last rank (green0/amber1/red2)

  void _setBanner(String txt, Color col) {
    _bannerTxt = txt;
    _bannerCol = col;
    _bannerAt = DateTime.now();
    if (mounted) setState(() {});
  }

  /// (B5) route-check ke REAL legs se offline alert-engine banao.
  /// Yahan se internet ke BINA bhi har fix pe alerts chalte hain.
  void _wireRulesFrom(Map<String, dynamic>? route) {
    final ls = (route?['legs'] as List?) ?? [];
    if (ls.length >= 2) {
      _rules = NavRules([
        for (final l in ls) [_legLat(l), _legLon(l)],
      ], offNm: _offCourseNm);
    } else {
      _rules = null;
    }
  }

  /// (B8) mini-map ko poore route pe auto-fit (route aate hi, ek baar)
  final _mapCtl = MapController();

  void _fitRoute(Map<String, dynamic>? r) {
    final ls = (r?['legs'] as List?) ?? [];
    if (ls.length < 2) return;
    final pts = [for (final l in ls) LatLng(_legLat(l), _legLon(l))];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapCtl.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.all(32)));
      } catch (_) {}
    });
  }

  /// (B8) FULL analysis screen — faisla kaunse numbers se bana, sab dikhe
  void _openAnalysis() {
    final tgt = widget.app.navTarget;
    if (tgt == null) return;
    final r = _route ??
        {
          // transit response me bhi legs+geometry hoti hai — usi ka fallback
          'legs': _rtAdv?['legs'],
          'ok': _rtAdv?['land_ok'],
          'detour': _rtAdv?['detour'],
          'reason': _rtAdv?['land_reason'],
          'distance_km': _rtAdv?['distance_km'],
          'distance_nm': _rtAdv?['distance_nm'],
          'bearing_deg': _rtAdv?['bearing_deg'],
        };
    final d = widget.app.demoOrigin;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RouteAnalysisScreen(
        route: r,
        rt: _rtAdv,
        rtErr: _rtAdvErr,
        startName: d != null
            ? '${d.latitude.toStringAsFixed(3)},${d.longitude.toStringAsFixed(3)}'
            : 'GPS',
        destName: tgt.name,
      ),
    ));
  }

  String _alertText(NavAlert a) => a.type == 'offcourse'
      ? 'al_offcourse'
          .tr(args: [a.nm.toStringAsFixed(1), a.deg.toStringAsFixed(0)])
      : a.type == 'turn'
          ? 'al_turn'
              .tr(args: [a.nm.toStringAsFixed(1), a.deg.toStringAsFixed(0)])
          : 'al_ontrack'.tr();

  void _tickAlerts(Position fix) {
    final rules = _rules;
    // (B6) plan-mode: naav sach me wahan nahi — live alerts honestly OFF
    if (rules == null || widget.app.navTarget == null ||
        widget.app.demoOrigin != null) return;
    for (final a in rules.tick(fix.latitude, fix.longitude)) {
      final col = a.type == 'offcourse'
          ? OrcaTheme.dangerRed
          : a.type == 'turn'
              ? OrcaTheme.warnAmber
              : OrcaTheme.okGreen;
      final txt = _alertText(a);
      _setBanner(txt, col);
      _notifyArrival(txt, a.type == 'ontrack' ? 11 : 10);
    }
  }

  /// (B5) destination conditions 15 min me do-jaanch — haalat BIGDI
  /// (green→amber→red) to skipper ko batao. Network chahiye; offline
  /// rahe to silently agle round pe try (koi fake data nahi).
  void _startWxWatcher() {
    _wxTimer?.cancel();
    _wxTimer = Timer.periodic(const Duration(minutes: 15), (t) async {
      final tgt = widget.app.navTarget;
      if (tgt == null || !mounted) {
        t.cancel();
        return;
      }
      try {
        final a = await OrcaApi.advisory(widget.settings.base, tgt.lat, tgt.lon);
        if (!mounted || widget.app.navTarget != tgt) return;
        final c = '${a['color']}';
        final rank = c == 'red'
            ? 2
            : c == 'amber'
                ? 1
                : c == 'green'
                    ? 0
                    : 1;
        if (rank > _tgtColorRank) {
          final txt = 'al_dest_worse'
              .tr(args: [rank == 2 ? 'rt_nogo'.tr() : 'rt_caution'.tr()]);
          _setBanner(txt, rank == 2 ? OrcaTheme.dangerRed : OrcaTheme.warnAmber);
          _notifyArrival(txt, 12);
        }
        _tgtColorRank = rank;
      } catch (_) {
        /* offline — agli baar try; kabhi status invent nahi karte */
      }
    });
  }

  /// (B4) "jahan ho se is point tak jaana safe?" — POORA rasta
  /// (~30km sampling + har point ka live marine data). GPS fix milte
  /// hi chalta hai; cooldown isliye taaki har GPS tick pe fire na ho.
  Future<void> _maybeRtAdv() async {
    final tgt = widget.app.navTarget;
    final org = _origin(); // (B6) manual start > GPS
    if (tgt == null || org == null) return;
    if (_rtAdvFor == tgt) return; // one-shot per target (in-flight bhi)
    _rtAdvFor = tgt;
    try {
      final r = await OrcaApi.routeAdvisory(
          widget.settings.base, org.lat, org.lon, tgt.lat, tgt.lon);
      if (mounted && widget.app.navTarget == tgt) {
        setState(() => _rtAdv = r);
      }
    } catch (e) {
      if (mounted && widget.app.navTarget == tgt) {
        setState(() => _rtAdvErr = e);
      }
    }
  }

  /// (B3) "is point pe jaana safe hai?" — target ki REAL advisory
  /// (waves/wind/SST verdict) — koi guess nahi, backend ka verdict.
  Future<void> _maybeTgtAdv() async {
    final tgt = widget.app.navTarget;
    if (tgt == null || _tgtAdvFor == tgt) return;
    _tgtAdvFor = tgt;
    _tgtAdv = null;
    _tgtAdvErr = null;
    try {
      final r = await OrcaApi.advisory(
          widget.settings.base, tgt.lat, tgt.lon);
      if (mounted && widget.app.navTarget == tgt) {
        setState(() => _tgtAdv = r);
        final c = '${r['color']}'; // (B5) rank sync — yahi baseline hai
        _tgtColorRank =
            c == 'red'
                ? 2
                : c == 'amber'
                    ? 1
                    : c == 'green'
                        ? 0
                        : 1;
      }
    } catch (e) {
      if (mounted && widget.app.navTarget == tgt) {
        setState(() => _tgtAdvErr = e);
      }
    }
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
    _maybeRtAdv(); // (B4) fix milte hi transit verdict (one-shot per target)
    _tickAlerts(fix); // (B5) live off-course / turn / recover alerts (offline)
    // wakelock: target hai to screen on rakho
    final wantWake = widget.app.navTarget != null;
    if (wantWake != _wakeOn) {
      _wakeOn = wantWake;
      wantWake ? WakelockPlus.enable() : WakelockPlus.disable();
    }
    setState(() {});
  }

  /// (B3) destination advisory state
  Map<String, dynamic>? _tgtAdv;
  Object? _tgtAdvErr;
  Object? _tgtAdvFor;

  /// route-check ke legs ARRAYS [[lat,lon]…] aate hain (backend
  /// routecheck.py: "from": [lat,lon]) — dict-shape bhi future me sambhalo.
  double _legLat(dynamic l) =>
      l is List ? (l[0] as num).toDouble() : (l['lat'] as num).toDouble();
  double _legLon(dynamic l) =>
      l is List ? (l[1] as num).toDouble() : (l['lon'] as num).toDouble();

  Future<void> _maybeRouteCheck() async {
    final tgt = widget.app.navTarget;
    final org = _origin(); // (B6) manual start > GPS
    if (tgt == null || org == null) return;
    if (_routeFor == tgt && _route != null) return;
    _routeFor = tgt;
    try {
      final r = await OrcaApi.routeCheck(
          widget.settings.base, org.lat, org.lon, tgt.lat, tgt.lon);
      if (mounted && widget.app.navTarget == tgt) {
        setState(() => _route = r);
        if (widget.app.demoOrigin == null) _wireRulesFrom(r); // (B5) live only
        _fitRoute(r); // (B8) mini-map route pe fit
      }
    } catch (e) {
      if (mounted && widget.app.navTarget == tgt) {
        setState(() => _route = {
              'ok': null,
              'reason': 'route-check failed: $e',
              'legs': [
                {'lat': org.lat, 'lon': org.lon},
                {'lat': tgt.lat, 'lon': tgt.lon},
              ],
            });
        if (widget.app.demoOrigin == null) _wireRulesFrom(_route);
        _fitRoute(_route); // (B8) fallback line pe bhi fit
      }
    }
  }

  void _checkArrival(Position fix) {
    final tgt = widget.app.navTarget;
    if (tgt == null || widget.app.demoOrigin != null) return; // (B6) plan-mode: arrival n/a
    final dNm = Marine.kmToNm(
        Marine.haversineKm(fix.latitude, fix.longitude, tgt.lat, tgt.lon));
    if (dNm <= _arriveNm && !_arrivedNotified) {
      _arrivedNotified = true;
      _notifyArrival('${tgt.name} — ${dNm.toStringAsFixed(1)} NM');
    } else if (dNm > _arriveNm * 2) {
      _arrivedNotified = false; // reset jab phir door jao
    }
  }

  // ── (B2) destination option tile ──
  Widget _destOpt(ThemeData t, IconData ic, String labelKey, Color color,
          VoidCallback? onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: double.infinity,
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: t.dividerColor)),
            child: ListTile(
              onTap: onTap,
              enabled: onTap != null,
              leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.15),
                  child: Icon(ic, size: 19, color: color)),
              title: Text(labelKey.tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
              trailing: Icon(
                  onTap == null
                      ? Icons.lock_outline_rounded
                      : Icons.chevron_right_rounded,
                  color: t.colorScheme.secondary,
                  size: 18),
            ),
          ),
        ),
      );

  /// 🏝️ Fas-gaya mode — GPS + bundled harbour list = 100% OFFLINE.
  /// Network ki zaroorat hi nahi; online ho to route-check baad me.
  Future<void> _returnToHarbour() async {
    Position? f = widget.app.lastFix;
    if (f == null) {
      try {
        f = await orcaFix();
      } catch (_) {
        f = null; // gps off / permission nahi — koi rona nahi, no-op
      }
    }
    if (f == null) return;
    Harbour? best;
    var bestKm = double.infinity;
    final ff = f;
    for (final h in kHarbours) {
      final d = Marine.haversineKm(ff.latitude, ff.longitude, h.lat, h.lon);
      if (d < bestKm) {
        bestKm = d;
        best = h;
      }
    }
    final h = best!;
    widget.app.setTarget(
        NavTarget(
            '🏝️ ${h.name} · ${Marine.kmToNm(bestKm).toStringAsFixed(0)} NM',
            h.lat,
            h.lon),
        ret: true);
  }

  // ── (B6) PLAN-ANYWHERE: effective start = manual demo-origin > GPS ──
  /// PLAN mode (manual set) me LIVE cheezein (steer/off-course/arrival,
  /// alert-ticks) honestly PAUSE hoti hain — naav sach me wahan nahi hai;
  /// planning (route + transit verdict + waypoint list) FULL chalti hai.
  ({double lat, double lon})? _origin() {
    final d = widget.app.demoOrigin;
    if (d != null) return (lat: d.latitude, lon: d.longitude);
    final f = _fix;
    return f == null ? null : (lat: f.latitude, lon: f.longitude);
  }

  /// (B6) origin badla → route/verdict/alerts sab re-compute (stale na rahe)
  void _invalidateRouteState() {
    _route = null;
    _routeFor = null;
    _rules = null;
    _rtAdv = null;
    _rtAdvFor = null;
    _rtAdvErr = null;
    _bannerTxt = null;
    _tgtColorRank = 1;
  }

  /// (B6) manual start point dialog — coords daalo, wahan se SAB kuch
  /// (route-check land verify, transit verdict, distance/bearing) chalega.
  Future<void> _startDialog() async {
    final d0 = widget.app.demoOrigin;
    final la = TextEditingController(
        text: d0 == null ? '' : d0.latitude.toStringAsFixed(4));
    final lo = TextEditingController(
        text: d0 == null ? '' : d0.longitude.toStringAsFixed(4));
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('nav_set_start'.tr()),
        content: Row(children: [
          Expanded(
              child: TextField(
                  controller: la,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Lat'))),
          const SizedBox(width: 10),
          Expanded(
              child: TextField(
                  controller: lo,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Lon'))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text('close_lbl'.tr())),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text('apply_lbl'.tr())),
        ],
      ),
    );
    if (ok == true) {
      final a = double.tryParse(la.text.trim());
      final o = double.tryParse(lo.text.trim());
      if (a != null && o != null && a.abs() <= 90 && o.abs() <= 180) {
        await widget.app.setDemoOrigin(LatLng(a, o));
        if (!mounted) return;
        _invalidateRouteState();
        _maybeRouteCheck();
        _maybeRtAdv();
        setState(() {});
      }
    }
  }

  /// (B6) wapas GPS mode — live navigation + alerts phir chalu.
  Future<void> _clearStart() async {
    await widget.app.setDemoOrigin(null);
    if (!mounted) return;
    _invalidateRouteState();
    _maybeRouteCheck();
    setState(() {});
  }

  Future<void> _coordsDialog() async {

    final la = TextEditingController();
    final lo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('nav_pick_coords'.tr()),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: la,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'lat')),
          TextField(
              controller: lo,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'lon')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('✕')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('apply_lbl'.tr())),
        ],
      ),
    );
    if (ok != true) return;
    final lat = double.tryParse(la.text.trim());
    final lon = double.tryParse(lo.text.trim());
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      return; // invalid input — kuch set nahi hua (honest no-op)
    }
    widget.app.setTarget(NavTarget(
        'manual ${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}',
        lat,
        lon));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    _wxTimer?.cancel();
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
      final probe = widget.app.probePoint;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        children: [
          Icon(Icons.explore_off_rounded,
              size: 46, color: t.colorScheme.secondary.withOpacity(0.7)),
          const SizedBox(height: 10),
          Text('nav_no_target'.tr(),
              textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
          const SizedBox(height: 18),
          _destOpt(
            t,
            Icons.anchor_rounded,
            'nav_pick_harbour',
            OrcaTheme.tealDeep,
            _returnToHarbour,
          ),
          _destOpt(
            t,
            Icons.touch_app_rounded,
            'nav_pick_tap',
            OrcaTheme.teal,
            probe == null
                ? null
                : () => widget.app.setTarget(NavTarget(
                    'map ${probe.latitude.toStringAsFixed(3)},${probe.longitude.toStringAsFixed(3)}',
                    probe.latitude,
                    probe.longitude)),
          ),
          _destOpt(
            t,
            Icons.edit_location_alt_rounded,
            'nav_pick_coords',
            OrcaTheme.warnAmber,
            _coordsDialog,
          ),
          // (B6) PLAN-ANYWHERE — manual start (Punjab baithe samundar ka route)
          _destOpt(
            t,
            Icons.my_location_rounded,
            widget.app.demoOrigin == null ? 'nav_set_start' : 'nav_start_gps',
            OrcaTheme.okGreen,
            widget.app.demoOrigin == null ? _startDialog : _clearStart,
          ),
          _destOpt(
            t,
            Icons.map_rounded,
            'pick_on_map',
            t.colorScheme.secondary,
            () => widget.app.jumpTab?.call(1),
          ),
          if (widget.app.demoOrigin != null) ...[
            const SizedBox(height: 8),
            Text('nav_demo_note'.tr(),
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.secondary)),
          ],
        ],
      );
    }

    final fix = _fix;
    final org = _origin(); // (B6) manual start > GPS
    final liveMode = widget.app.demoOrigin == null; // plan-mode: live cheezein pause
    // distKm ek hi baar — distNm + ETA dono isi se derive (promotion-safe)
    final distKm = org == null
        ? null
        : Marine.haversineKm(org.lat, org.lon, tgt.lat, tgt.lon);
    final distNm = distKm == null ? null : Marine.kmToNm(distKm);
    final brg = org == null
        ? null
        : Marine.bearingDeg(org.lat, org.lon, tgt.lat, tgt.lon);
    final speedKn = fix == null ? 0.0 : fix.speed * 1.943844;
    final etaTxt =
        liveMode && distKm != null ? Marine.eta(distKm, speedKn) : null;
    // cross-track vs best leg (LIVE mode only — demo origin pe GPS naav se door hai)
    double? xtrackNm;
    var bestI = 0; // (B3) closest segment — next waypoint isi se niklega
    final legs = (_route?['legs'] as List?) ?? [];
    if (liveMode && fix != null && legs.length >= 2) {
      var best = double.infinity;
      for (var i = 0; i + 1 < legs.length; i++) {
        final a = legs[i], b = legs[i + 1];
        final d = Marine.crossTrackKm(fix.latitude, fix.longitude, _legLat(a),
            _legLon(a), _legLat(b), _legLon(b));
        if (d < best) {
          best = d;
          bestI = i;
        }
      }
      if (best.isFinite) xtrackNm = Marine.kmToNm(best);
    }
    final offCourse =
        liveMode && xtrackNm != null && xtrackNm > _offCourseNm;
    final arrived =
        liveMode && distNm != null && distNm <= _arriveNm;
    // (B3) agla waypoint — Google-maps style "next 245° · 0.8 NM"
    // (B6: waypoint list LEGS se^ neeche dikhti hai; HUD cue live-mode only)
    String? wpTxt;
    if (liveMode && fix != null && legs.length >= 2) {
      final wp = legs[(bestI + 1).clamp(1, legs.length - 1)];
      final wLat = _legLat(wp), wLon = _legLon(wp);
      final wb = Marine.bearingDeg(fix.latitude, fix.longitude, wLat, wLon);
      final wd = Marine.kmToNm(
          Marine.haversineKm(fix.latitude, fix.longitude, wLat, wLon));
      if (wd > 0.05) {
        wpTxt =
            '${wb.toStringAsFixed(0).padLeft(3, '0')}° ${wd.toStringAsFixed(1)}NM';
      }
    }
    final steer = (liveMode && fix != null && speedKn > 1.0 && brg != null)
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
      // ── (B5) LIVE ALERT banner — 60s tak fresh dikhta hai ──
      if (_bannerTxt != null &&
          _bannerAt != null &&
          DateTime.now().difference(_bannerAt!) < const Duration(seconds: 60))
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: (_bannerCol ?? OrcaTheme.warnAmber).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _bannerCol ?? OrcaTheme.warnAmber)),
          child: Row(children: [
            Icon(Icons.notifications_active_rounded,
                color: _bannerCol ?? OrcaTheme.warnAmber, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_bannerTxt!,
                  style: t.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _bannerCol ?? OrcaTheme.warnAmber)),
            ),
          ]),
        ),
      // ── mini map ──
      SizedBox(
        height: 220,
        child: FlutterMap(
          mapController: _mapCtl, // (B8) route pe auto-fit
          options: MapOptions(
            initialCenter: org != null
                ? LatLng(org.lat, org.lon)
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
                    for (final l in legs) LatLng(_legLat(l), _legLon(l))
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
          if (widget.app.returnToHarbour)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: OrcaTheme.mintChip,
                    borderRadius: BorderRadius.circular(99)),
                child: Text('nav_return_badge'.tr(),
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ),
          IconButton(
              onPressed: () {
                widget.app.clearTarget();
                _route = null;
                _routeFor = null;
                _tgtAdv = null;
                _tgtAdvFor = null;
                _tgtAdvErr = null;
                _rtAdv = null;
                _rtAdvFor = null;
                _rtAdvErr = null;
                _rules = null;
                _bannerTxt = null;
                _wxTimer?.cancel();
                if (_wakeOn) WakelockPlus.disable();
                _wakeOn = false;
                setState(() {});
              },
              icon: Icon(Icons.close_rounded,
                  size: 20, color: t.colorScheme.secondary)),
        ]),
      ),
      // ── (B6) START chip — kahan SE: live GPS ya manual plan-point ──
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        child: GestureDetector(
          onTap: widget.app.demoOrigin == null ? _startDialog : _clearStart,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: OrcaTheme.mintChip,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(children: [
              Icon(Icons.my_location_rounded,
                  size: 14,
                  color: widget.app.demoOrigin == null
                      ? OrcaTheme.okGreen
                      : OrcaTheme.warnAmber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.app.demoOrigin == null
                      ? 'nav_start_gps'.tr()
                      : 'nav_start_manual'.tr(args: [
                          widget.app.demoOrigin!.latitude.toStringAsFixed(3),
                          widget.app.demoOrigin!.longitude.toStringAsFixed(3),
                        ]),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.swap_horiz_rounded,
                  size: 16, color: t.colorScheme.secondary),
            ]),
          ),
        ),
      ),
      if (widget.app.demoOrigin != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 3, 16, 0),
          child: Text('nav_demo_note'.tr(),
              style: t.textTheme.bodySmall
                  ?.copyWith(color: OrcaTheme.warnAmber, fontSize: 10.5)),
        ),
      // ── (B3) destination conditions — advisory@target (REAL verdict) ──
      if (_tgtAdv != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: Builder(builder: (ctx) {
            final a = _tgtAdv!;
            final c = '${a['color']}';
            final col = c == 'green'
                ? OrcaTheme.okGreen
                : c == 'red'
                    ? OrcaTheme.dangerRed
                    : OrcaTheme.warnAmber;
            final isHi = Localizations.localeOf(ctx).languageCode != 'en';
            final v = (a['variables'] as Map?) ?? const {};
            String m(String k, String u, [int dp = 1]) => v[k] is num
                ? '${(v[k] as num).toStringAsFixed(dp)}$u'
                : '—';
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: col.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: col.withOpacity(0.6)),
              ),
              child: Row(children: [
                Icon(Icons.sailing_rounded, color: col, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            isHi
                                ? '${a['headline_hi'] ?? a['headline']}'
                                : '${a['headline']}',
                            style: t.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800, color: col),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        Text(
                            '🌊 ${m('wave_height_m', 'm')} · 💨 ${m('wind_kts', 'kn', 0)} · 🌡 ${m('sst_c', '°')}',
                            style: t.textTheme.bodySmall),
                      ]),
                ),
              ]),
            );
          }),
        )
      else if (_tgtAdvErr != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: Row(children: [
            Expanded(
              child: Text('ra_dest_failed'.tr(),
                  style: t.textTheme.bodySmall
                      ?.copyWith(color: OrcaTheme.warnAmber)),
            ),
            IconButton(
              onPressed: () {
                _tgtAdvFor = null;
                _tgtAdvErr = null;
                _maybeTgtAdv();
              },
              icon: Icon(Icons.refresh_rounded,
                  size: 18, color: t.colorScheme.secondary),
              tooltip: 'ra_retry'.tr(),
            ),
          ]),
        ),
      // ── (B4) TRANSIT VERDICT — poore raste ka final faisla ──
      if (widget.app.navTarget != null)
        if (_rtAdv != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Builder(builder: (ctx) {
              final r = _rtAdv!;
              final v = (r['verdict'] as Map?) ?? const {};
              final level = '${v['level']}';
              final col = level == 'go'
                  ? OrcaTheme.okGreen
                  : level == 'nogo'
                      ? OrcaTheme.dangerRed
                      : level == 'caution'
                          ? OrcaTheme.warnAmber
                          : t.colorScheme.secondary;
              final titleKey = level == 'go'
                  ? 'rt_go'
                  : level == 'nogo'
                      ? 'rt_nogo'
                      : level == 'caution'
                          ? 'rt_caution'
                          : 'rt_unknown';
              final pts = ((r['points'] as List?) ?? const []);
              String m(dynamic x, String u, [int dp = 1]) =>
                  x is num ? '${x.toStringAsFixed(dp)}$u' : '—';
              Color dot(String s) => s == 'good'
                  ? OrcaTheme.okGreen
                  : s == 'danger'
                      ? OrcaTheme.dangerRed
                      : s == 'caution'
                          ? OrcaTheme.warnAmber
                          : Colors.grey;
              final landOk = r['land_ok'];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: col.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: col.withOpacity(0.7), width: 1.5),
                ),
                child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.alt_route_rounded, color: col, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('rt_heading'.tr(),
                          style: t.textTheme.bodySmall
                              ?.copyWith(color: t.colorScheme.secondary)),
                    ),
                    Text(
                        'rt_pts'.tr(args: [
                          '${v['points_known'] ?? 0}',
                          '${v['points_total'] ?? 0}'
                        ]),
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: t.colorScheme.secondary)),
                  ]),
                  const SizedBox(height: 4),
                  Text(titleKey.tr(),
                      style: t.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900, color: col, fontSize: 22)),
                  if (landOk == false || r['detour'] == true || landOk == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        landOk == false
                            ? 'rt_land_blocked'.tr()
                            : r['detour'] == true
                                ? 'rt_land_detour'.tr()
                                : 'rt_land_unverified'.tr(),
                        style: t.textTheme.bodySmall?.copyWith(
                            color: r['detour'] == true
                                ? OrcaTheme.okGreen
                                : OrcaTheme.warnAmber,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  const Divider(height: 14),
                  for (final p in pts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.circle, size: 10, color: dot('${p['state']}')),
                              const SizedBox(width: 6),
                              Text('rt_km'.tr(args: ['${p['sail_km'] ?? 0}']),
                                  style: t.textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${p['state']}' == 'unknown'
                                      ? '—'
                                      : '🌊 ${m(p['wave_m'], 'm')}  💨 ${m(p['wind_kn'], 'kn', 0)}',
                                  style: t.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]),
                            if (p['why'] != null || p['note'] != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: Text('${p['why'] ?? p['note']}',
                                    style: t.textTheme.bodySmall?.copyWith(
                                        color: ('${p['state']}' == 'danger')
                                            ? OrcaTheme.dangerRed
                                            : t.colorScheme.secondary,
                                        fontSize: 11)),
                              ),
                          ]),
                    ),
                  if ((r['safe_window_at_start'] as Map?)?['found'] == true) ...[
                    const Divider(height: 12),
                    Text('⏱ ${'rt_window'.tr()}: ${r['safe_window_at_start']['note'] ?? ''}',
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: OrcaTheme.okGreen, fontSize: 11)),
                  ],
                  if ((((r['sources_used'] as List?) ?? const []).isNotEmpty) ||
                      (((r['sources_failed'] as List?) ?? const []).isNotEmpty))
                    ExpansionTile(
                      dense: true,
                      tilePadding: EdgeInsets.zero,
                      title: Text('ai_sources_ok'.tr(),
                          style: t.textTheme.bodySmall
                              ?.copyWith(color: t.colorScheme.secondary, fontSize: 11)),
                      children: [
                        for (final s in ((r['sources_used'] as List?) ?? const []))
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('✔ $s',
                                style: t.textTheme.bodySmall
                                    ?.copyWith(fontSize: 11, color: OrcaTheme.okGreen)),
                          ),
                        for (final s in ((r['sources_failed'] as List?) ?? const []))
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('✘ $s',
                                style: t.textTheme.bodySmall
                                    ?.copyWith(fontSize: 11, color: OrcaTheme.dangerRed)),
                          ),
                      ],
                    ),
                  // ── (B8) FULL ROUTE ANALYSIS screen ──
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _openAnalysis,
                      icon: const Icon(Icons.analytics_rounded, size: 16),
                      label: Text('ra_open'.tr(),
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ]),
              );
            }),
          )
        else if (_rtAdvErr != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: OrcaTheme.dangerRed.withOpacity(0.5))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('rt_failed'.tr(),
                    style: t.textTheme.bodySmall?.copyWith(
                        color: OrcaTheme.dangerRed, fontWeight: FontWeight.w800)),
                Text('$_rtAdvErr',
                    style: t.textTheme.bodySmall?.copyWith(
                        fontSize: 10, color: t.colorScheme.secondary)),
                Row(children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _rtAdvFor = null;
                        _rtAdvErr = null;
                      });
                      _maybeRtAdv();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text('ra_retry'.tr(),
                        style: const TextStyle(fontSize: 12)),
                  ),
                  TextButton.icon(
                    onPressed: _openAnalysis,
                    icon: const Icon(Icons.analytics_rounded, size: 16),
                    label: Text('ra_open'.tr(),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ]),
              ]),
            ),
          )
        else if (_fix != null || widget.app.demoOrigin != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Row(children: [
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('rt_loading'.tr(),
                  style: t.textTheme.bodySmall
                      ?.copyWith(color: t.colorScheme.secondary)),
            ]),
          ),
      // ── HUD ──
      Expanded(
        child: _gpsErr != null && widget.app.demoOrigin == null
            ? Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.gps_off_rounded,
                          size: 40, color: OrcaTheme.warnAmber),
                      const SizedBox(height: 12),
                      Text('nav_gps_no_fix'.tr(),
                          textAlign: TextAlign.center,
                          style: t.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: OrcaTheme.warnAmber)),
                      const SizedBox(height: 8),
                      Text('nav_gps_hint'.tr(),
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodySmall
                              ?.copyWith(color: t.colorScheme.secondary)),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _startDialog,
                        icon: const Icon(Icons.my_location_rounded, size: 17),
                        label: Text('nav_use_manual'.tr()),
                      ),
                      TextButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.refresh_rounded, size: 17),
                        label: Text('nav_retry_gps'.tr()),
                      ),
                      const SizedBox(height: 6),
                      // raw error honestly, chhota — fisherman ko upar wala
                      // button chahiye, judge ko yeh detail
                      Text(_gpsErr ?? '',
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodySmall?.copyWith(
                              color: t.colorScheme.secondary, fontSize: 10)),
                    ]),
                  ),
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
                  _Hud('eta_lbl'.tr(), etaTxt ?? '—', OrcaTheme.okGreen),
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
                      wpTxt ?? steerTxt ?? (arrived ? '🐟' : '—'),
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
              onPressed: () => widget.app.jumpTab?.call(4),
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
