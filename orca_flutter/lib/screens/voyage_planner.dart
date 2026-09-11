import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api.dart';
import '../data/harbours.dart';
import '../state.dart';
import '../theme.dart';
import 'point_analysis.dart';
import 'route_analysis.dart';

/// (B16) VOYAGE PLANNER — web-lab (B10→B15) ka 1:1 mobile port.
///
/// Flow mockup-locked hai (user-generated samples, 2026-09-10):
///   STEP 1 intent  — 🎣 fish spots / ⚓ kahin jaana hai (+ trusted sources strip)
///   STEP 2 start   — GPS / harbour list+chips / coordinates / map-tap
///   STEP 3 fish    — reco cards: kind chip · score + strike base · stats ·
///                    state pill · 👥 crowd badge (B14) · 🚢 stale note (B15) ·
///                    auditable score breakdown · "course banao"
///   STEP 3 transit — dest pick + AUTO-SAFETY PROTOCOL box → RouteAnalysisScreen.
///
/// Koi dummy/dummy-number yahan kabhi nahi: har figure OrcaApi ke REAL
/// response se aata hai; fail hua to honest error/note dikhta hai.
/// Theme-aware: dark/dhoop mode = mockup navy tokens, light = app theme.
class VoyagePlannerScreen extends StatefulWidget {
  final Settings settings;
  final AppState app;
  const VoyagePlannerScreen({super.key, required this.settings, required this.app});

  @override
  State<VoyagePlannerScreen> createState() => _VoyagePlannerState();
}

enum _VpStep { intent, start, fish, transit }

/// Mockup lab palette — dark mode me exact sample colors, light me app theme.
class _Lab {
  _Lab(this.t) : dark = t.brightness == Brightness.dark;
  final ThemeData t;
  final bool dark;

  static const sky = Color(0xFF38BDF8);
  static const tealBr = Color(0xFF2DD4BF);
  static const violet = Color(0xFFA78BFA);
  static const emerald = Color(0xFF34D399);
  static const amber = Color(0xFFFBBF24);
  static const rose = Color(0xFFFB7185);
  static const slate = Color(0xFF94A3B8);

  Color get bg => dark ? const Color(0xFF0A0E1A) : t.scaffoldBackgroundColor;
  Color get card => dark ? const Color(0xFF121A2E) : t.cardColor;
  Color get line => dark ? const Color(0xFF1E2A44) : t.dividerColor;
  Color get body => dark ? const Color(0xFF9FB0D1) : OrcaTheme.subText;
  Color get faint => dark ? const Color(0xFF4D5D80) : Colors.grey;
  Color get white => dark ? Colors.white : OrcaTheme.inkText;
}

class _VoyagePlannerState extends State<VoyagePlannerScreen> {
  _VpStep _step = _VpStep.intent;
  String _intent = ''; // 'fish' | 'transit'

  double? _sLat, _sLon, _dLat, _dLon;
  String _startName = '', _destName = '';
  Harbour? _sHar, _dHar;
  final _sLatC = TextEditingController(),
      _sLonC = TextEditingController(),
      _dLatC = TextEditingController(),
      _dLonC = TextEditingController();

  bool _gpsBusy = false;
  String? _gpsErr;
  bool _voyBusy = false;
  Map<String, dynamic>? _voy;
  Object? _voyErr;
  bool _rtBusy = false;

  @override
  void dispose() {
    _sLatC.dispose();
    _sLonC.dispose();
    _dLatC.dispose();
    _dLonC.dispose();
    super.dispose();
  }

  // ── state setters ────────────────────────────────────────────────
  void _setStart(double la, double lo, String name, {Harbour? h}) {
    setState(() {
      _sLat = la;
      _sLon = lo;
      _startName = name;
      _sHar = h;
    });
  }

  void _setDest(double la, double lo, String name, {Harbour? h}) {
    setState(() {
      _dLat = la;
      _dLon = lo;
      _destName = name;
      _dHar = h;
    });
  }

  Future<void> _useGps() async {
    setState(() {
      _gpsBusy = true;
      _gpsErr = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _gpsErr = 'nav_gps_no_fix';
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        _gpsErr = 'nav_gps_no_fix';
        return;
      }
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
            timeLimit: const Duration(seconds: 12));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        _gpsErr = 'nav_gps_no_fix';
        return;
      }
      widget.app.lastFix = pos;
      _setStart(pos.latitude, pos.longitude, 'GPS');
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
  }

  void _applyManualCoords(bool isStart) {
    final la = double.tryParse((isStart ? _sLatC : _dLatC).text.trim());
    final lo = double.tryParse((isStart ? _sLonC : _dLonC).text.trim());
    if (la == null || lo == null) return;
    if (la < -90 || la > 90 || lo < -180 || lo > 180) return;
    final nm = '✏️ ${la.toStringAsFixed(3)}, ${lo.toStringAsFixed(3)}';
    if (isStart) {
      _setStart(la, lo, nm);
    } else {
      _setDest(la, lo, nm);
    }
  }

  // ── API flows ────────────────────────────────────────────────────
  Future<void> _runVoyage() async {
    final la = _sLat, lo = _sLon;
    if (la == null || lo == null) {
      setState(() => _step = _VpStep.start);
      return;
    }
    setState(() {
      _voyBusy = true;
      _voyErr = null;
      _voy = null;
    });
    try {
      final v = await OrcaApi.voyage(widget.settings.base, la, lo);
      if (!mounted) return;
      setState(() {
        _voy = v;
        _step = _VpStep.fish;
      });
    } catch (e) {
      if (mounted) setState(() => _voyErr = e);
    } finally {
      if (mounted) setState(() => _voyBusy = false);
    }
  }

  Future<void> _analyze() async {
    final la = _sLat, lo = _sLon, da = _dLat, db = _dLon;
    if (la == null || lo == null || da == null || db == null) return;
    setState(() => _rtBusy = true);
    Map<String, dynamic>? route;
    Map<String, dynamic>? rt;
    Object? rtErr;
    try {
      route = await OrcaApi.routeCheck(widget.settings.base, la, lo, da, db);
    } catch (e) {
      rtErr = e;
    }
    if (route != null) {
      try {
        rt = await OrcaApi.routeAdvisory(widget.settings.base, la, lo, da, db);
      } catch (e) {
        rtErr = e;
      }
    }
    if (!mounted) return;
    setState(() => _rtBusy = false);
    final r0 = route;
    if (r0 == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('route-check failed — $rtErr',
              style: const TextStyle(fontSize: 13))));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RouteAnalysisScreen(
        route: r0,
        rt: rt,
        rtErr: rtErr,
        startName: _startName.isEmpty ? 'start' : _startName,
        destName: _destName.isEmpty ? 'destination' : _destName,
      ),
    ));
  }

  // ── small helpers ────────────────────────────────────────────────
  String _compass(double b) {
    const d = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return d[((b % 360) / 45).round() % 8];
  }

  String _n(dynamic v, [int dp = 1]) => v is num ? v.toStringAsFixed(dp) : '—';

  Widget _pill(_Lab lab, String txt, Color c,
      {bool outline = false, double fs = 10.5}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.55)),
      ),
      child: Text(txt,
          style: TextStyle(
              fontSize: fs, fontWeight: FontWeight.w800, color: c)),
    );
  }

  Widget _bigBtn(Color bg, String label, VoidCallback? onTap,
      {bool busy = false}) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: const Color(0xFF06201C),
          disabledBackgroundColor: bg.withOpacity(0.45),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: busy
            ? const SizedBox(
                height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _outBtn(_Lab lab, IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: _Lab.sky),
        label: Text(label, style: TextStyle(color: lab.body, fontSize: 13.5)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: lab.line),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Harbour? _matchHarbour(String frag) {
    for (final h in kHarbours) {
      if (h.name.toLowerCase().contains(frag.toLowerCase())) return h;
    }
    return null;
  }

  Widget _harbourDrop(
      _Lab lab, Harbour? value, ValueChanged<Harbour> onPick) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: lab.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: lab.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Harbour>(
          value: value,
          isExpanded: true,
          dropdownColor: lab.card,
          iconEnabledColor: _Lab.tealBr,
          hint: Text('nav_pick_harbour'.tr(),
              style: TextStyle(color: lab.faint, fontSize: 13)),
          items: [
            for (final h in kHarbours)
              DropdownMenuItem(
                value: h,
                child: Text(h.name,
                    style: TextStyle(color: lab.body, fontSize: 13.5)),
              )
          ],
          onChanged: (h) {
            if (h != null) onPick(h);
          },
        ),
      ),
    );
  }

  // ══ BUILD ═══════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final lab = _Lab(Theme.of(context));
    return Scaffold(
      backgroundColor: lab.bg,
      body: SafeArea(
        child: Column(children: [
          _header(lab),
          Expanded(
            child: (_voyBusy || _rtBusy)
                ? _loadingPanel(lab)
                : switch (_step) {
                    _VpStep.intent => _intentView(lab),
                    _VpStep.start => _startView(lab),
                    _VpStep.fish => _fishView(lab),
                    _VpStep.transit => _transitView(lab),
                  },
          ),
        ]),
      ),
    );
  }

  Widget _header(_Lab lab) {
    final canBack = _step != _VpStep.intent && !_voyBusy && !_rtBusy;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: lab.line, width: 1))),
      child: Row(children: [
        if (canBack)
          GestureDetector(
            onTap: () => setState(() {
              if (_step == _VpStep.fish || _step == _VpStep.transit) {
                _step = _VpStep.start;
              } else {
                _step = _VpStep.intent;
              }
            }),
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: lab.body),
            ),
          ),
        const Text('🧭', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('vp_title'.tr(),
                style: TextStyle(
                    color: lab.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            Text('vp_sub'.tr(),
                style: TextStyle(color: lab.faint, fontSize: 10.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _loadingPanel(_Lab lab) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              height: 34,
              width: 34,
              child: CircularProgressIndicator(strokeWidth: 2.6)),
          const SizedBox(height: 16),
          Text('vp_loading'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: lab.body, fontSize: 12.5, height: 1.5)),
        ]),
      ),
    );
  }

  // ── STEP 1 · intent (mockup 1) ───────────────────────────────────
  Widget _intentView(_Lab lab) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _intentCard(lab,
          emoji: '🎣',
          title: 'wiz_fish'.tr(),
          sub: 'vp_fish_s'.tr(),
          btn: 'vp_fish_b'.tr(),
          color: _Lab.tealBr, onTap: () {
        _intent = 'fish';
        if (_sLat != null) {
          _runVoyage();
        } else {
          setState(() => _step = _VpStep.start);
        }
      }),
      const SizedBox(height: 14),
      _intentCard(lab,
          emoji: '⚓',
          title: 'vp_go_t'.tr(),
          sub: 'vp_go_s'.tr(),
          btn: 'vp_go_b'.tr(),
          color: _Lab.sky, onTap: () {
        _intent = 'transit';
        setState(() => _step =
            _sLat != null ? _VpStep.transit : _VpStep.start);
      }),
      const SizedBox(height: 26),
      Text('vp_trusted'.tr(),
          style:
              TextStyle(color: lab.faint, fontSize: 10, letterSpacing: 1.4)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in const [
          'ISRO MOSDAC',
          'NOAA',
          'INCOIS PFZ',
          'GFW',
          'Open-Meteo'
        ])
          _pill(lab, s, lab.body == OrcaTheme.subText ? OrcaTheme.teal : _Lab.slate,
              outline: true, fs: 9.5),
      ]),
    ]);
  }

  Widget _intentCard(_Lab lab,
      {required String emoji,
      required String title,
      required String sub,
      required String btn,
      required Color color,
      required VoidCallback onTap}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: lab.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.16), blurRadius: 22)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
                color: color.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999)),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: lab.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 10),
        Text(sub, style: TextStyle(color: lab.body, fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 14),
        _bigBtn(color, btn, onTap),
      ]),
    );
  }

  // ── STEP 2 · start point (mockup 2) ──────────────────────────────
  Widget _startView(_Lab lab) {
    final probe = widget.app.probePoint;
    final popular = <Harbour>[
      for (final frag in const [
        'Chennai',
        'Kochi',
        'Mumbai',
        'Veraval',
        'Paradeep',
        'Tuticorin'
      ])
        if (_matchHarbour(frag) != null) _matchHarbour(frag)!,
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('vp_start_t'.tr(),
          style: TextStyle(
              color: lab.white, fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('vp_sub'.tr(), style: TextStyle(color: lab.faint, fontSize: 11)),
      const SizedBox(height: 14),

      // saved start chip
      if (_sLat != null)
        _pill(lab, '🚩 ${_startName.isEmpty ? '✓' : _startName}', _Lab.emerald),
      if (_sLat != null) const SizedBox(height: 10),

      // GPS primary
      _bigBtn(
          _Lab.tealBr,
          _gpsBusy
              ? '…'
              : '📍 ${'wiz_gps'.tr()}  ·  ${'vp_gps_n'.tr()}',
          _useGps,
          busy: _gpsBusy),
      if (_gpsErr != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('nav_gps_no_fix'.tr(),
              style: const TextStyle(color: _Lab.rose, fontSize: 11.5)),
        ),
      const SizedBox(height: 14),

      // harbour picker + chips
      Text('⚓ ${'nav_pick_harbour'.tr()}',
          style: TextStyle(color: lab.body, fontSize: 12.5)),
      const SizedBox(height: 8),
      _harbourDrop(lab, _sHar,
          (h) => _setStart(h.lat, h.lon, h.name, h: h)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final h in popular)
          GestureDetector(
              onTap: () => _setStart(h.lat, h.lon, h.name, h: h),
              child: _pill(lab, h.name.split(' ').first, _Lab.slate,
                  outline: true)),
      ]),
      const SizedBox(height: 14),

      // map-tap flow
      _outBtn(lab, Icons.map_rounded, 'nav_pick_tap'.tr(), () {
        widget.app.jumpTab?.call(1);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('vp_hint_tap'.tr())));
      }),
      if (probe != null) ...[
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _setStart(probe.latitude, probe.longitude,
              '🗺️ ${probe.latitude.toStringAsFixed(3)}, ${probe.longitude.toStringAsFixed(3)}'),
          child: _pill(lab,
              '🗺️ ${'vp_use_tapped'.tr()} (${probe.latitude.toStringAsFixed(3)}, ${probe.longitude.toStringAsFixed(3)})',
              _Lab.sky),
        ),
      ],
      const SizedBox(height: 14),

      // manual coords
      Text('✏️ ${'wiz_coords'.tr()}',
          style: TextStyle(color: lab.body, fontSize: 12.5)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: _coordField(lab, _sLatC, '${'vp_lat'.tr()} 13.0827')),
        const SizedBox(width: 8),
        Expanded(
            child: _coordField(lab, _sLonC, '${'vp_lon'.tr()} 80.2707')),
      ]),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () => _applyManualCoords(true),
          child: _pill(lab, 'vp_apply'.tr(), _Lab.tealBr),
        ),
      ),
      const SizedBox(height: 18),

      // honesty hint box (mockup 2 bottom)
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _Lab.amber.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Lab.amber.withOpacity(0.35)),
        ),
        child: Text('vp_hint_gps'.tr(),
            style: const TextStyle(
                color: _Lab.amber, fontSize: 11.5, height: 1.5)),
      ),
      const SizedBox(height: 18),

      if (_sLat != null)
        _bigBtn(
            _Lab.sky,
            _intent == 'fish' ? 'vp_fish_b'.tr() : 'vp_go_b'.tr(),
            () => _intent == 'fish'
                ? _runVoyage()
                : setState(() => _step = _VpStep.transit)),
    ]);
  }

  Widget _coordField(_Lab lab, TextEditingController c, String hint) {
    return TextField(
      controller: c,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: true),
      style: TextStyle(color: lab.white, fontSize: 13.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(color: lab.faint, fontSize: 12),
        filled: true,
        fillColor: lab.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: lab.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: lab.line)),
      ),
    );
  }

  // ── STEP 3 · fish reco cards (mockup 3) ──────────────────────────
  Widget _fishView(_Lab lab) {
    if (_voyErr != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('wiz_no_reco'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: lab.body, fontSize: 13)),
          const SizedBox(height: 6),
          Text('$_voyErr',
              textAlign: TextAlign.center,
              style: TextStyle(color: lab.faint, fontSize: 10.5)),
          const SizedBox(height: 14),
          _bigBtn(_Lab.tealBr, 'vp_apply'.tr(), _runVoyage),
        ]),
      ));
    }
    final v = _voy;
    if (v == null) return _loadingPanel(lab);
    final recs = (v['recommendations'] as List?) ?? const [];
    final notes = (v['notes'] as List?) ?? const [];
    final found = v['found'] == true && recs.isNotEmpty;
    return ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [
        Expanded(
          child: Text('vp_best_t'.tr(),
              style: TextStyle(
                  color: lab.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
        ),
        GestureDetector(
            onTap: () => setState(() => _step = _VpStep.start),
            child: _pill(lab, 'vp_change_start'.tr(), _Lab.slate,
                outline: true)),
      ]),
      Text('vp_best_s'.tr(), style: TextStyle(color: lab.faint, fontSize: 10.5)),
      if (notes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final n in notes.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $n',
                    style: TextStyle(color: lab.faint, fontSize: 9.5, height: 1.4)),
              ),
          ]),
        ),
      const SizedBox(height: 10),
      if (!found)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('wiz_no_reco'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: lab.body, fontSize: 13)),
        ),
      for (final r in recs)
        if (r is Map) _recoCard(lab, r.cast<String, dynamic>()),
    ]);
  }

  Widget _recoCard(_Lab lab, Map<String, dynamic> r) {
    final pf = '${r['kind']}' == 'pfz';
    final kindCol = pf ? _Lab.tealBr : _Lab.violet;
    final score = r['score'];
    final base = r['score_base'];
    final crowd = r['crowd'] is Map
        ? (r['crowd'] as Map).cast<String, dynamic>()
        : null;
    final reasons = (r['reasons'] as List?) ?? const [];
    final why = r['why'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: lab.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lab.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // row 1 — kind chip · name · score
        Row(children: [
          _pill(lab, pf ? 'OFFICIAL PFZ ✓' : 'CHL HOTSPOT ⌖', kindCol, fs: 9.5),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${r['name'] ?? ''}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: lab.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800)),
          ),
          Column(children: [
            Text(score is num ? '${score.toInt()}' : '??',
                style: const TextStyle(
                    color: _Lab.sky,
                    fontSize: 19,
                    fontWeight: FontWeight.w800)),
            if (base is num && score is num && base.toInt() != score.toInt())
              Text('${base.toInt()}',
                  style: TextStyle(
                      color: lab.faint,
                      fontSize: 10,
                      decoration: TextDecoration.lineThrough)),
          ]),
        ]),
        const SizedBox(height: 8),

        // row 2 — stats
        Wrap(spacing: 10, runSpacing: 4, children: [
          Text(
              '🧭 ${_n(r['distance_nm'])} NM · ${_compass((r['bearing_deg'] as num?)?.toDouble() ?? 0)} (${_n(r['bearing_deg'], 0)}°)',
              style: TextStyle(color: lab.body, fontSize: 11.5)),
          if (r['wave_m'] != null)
            Text('🌊 ${_n(r['wave_m'])} m',
                style: TextStyle(color: lab.body, fontSize: 11.5)),
          if (r['wind_kn'] != null)
            Text('💨 ${_n(r['wind_kn'], 1)} kn',
                style: TextStyle(color: lab.body, fontSize: 11.5)),
          if (r['sst_c'] != null)
            Text('🌡️ ${_n(r['sst_c'])} °C',
                style: TextStyle(color: lab.body, fontSize: 11.5)),
          if (r['chl'] != null)
            Text('🦠 chl ${_n(r['chl'])}',
                style: TextStyle(color: lab.body, fontSize: 11.5)),
        ]),
        const SizedBox(height: 8),

        // row 3 — state pill + crowd badge (B14)
        Wrap(spacing: 8, runSpacing: 6, children: [
          _statePill(lab, '${r['state']}'),
          if (crowd != null) _crowdBadge(lab, crowd),
        ]),

        // B15 stale note
        if (crowd != null && crowd['note'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text('🚢 ${crowd['note']}',
                style: TextStyle(color: lab.faint, fontSize: 9.8, height: 1.4)),
          ),

        // why (weather reason)
        if (why != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text('$why',
                style: const TextStyle(
                    color: _Lab.amber,
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    height: 1.4)),
          ),

        // auditable breakdown
        if (reasons.isNotEmpty)
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              dense: true,
              iconColor: lab.faint,
              collapsedIconColor: lab.faint,
              title: Text('vp_break'.tr(),
                  style: TextStyle(color: lab.faint, fontSize: 10.5)),
              children: [
                for (final rs in reasons)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('· $rs',
                        style: TextStyle(
                            color: lab.body, fontSize: 10.5, height: 1.5)),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),

        // CTA → transit pre-filled
        Row(children: [
          Expanded(
            child: _bigBtn(_Lab.tealBr, '${'wiz_set_target'.tr()} ➜', () {
              final la = (r['lat'] as num?)?.toDouble();
              final lo = (r['lon'] as num?)?.toDouble();
              if (la == null || lo == null) return;
              _intent = 'transit';
              _setDest(la, lo, '${r['name'] ?? 'spot'}');
              setState(() => _step = _VpStep.transit);
            }),
          ),
          const SizedBox(width: 8),
          // (B17) 🤖 — is spot ka environment + 10-agent analysis
          OutlinedButton(
            onPressed: () {
              final la = (r['lat'] as num?)?.toDouble();
              final lo = (r['lon'] as num?)?.toDouble();
              if (la == null || lo == null) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PointAnalysisScreen(
                  settings: widget.settings,
                  app: widget.app,
                  lat: la,
                  lon: lo,
                  name: '${r['name'] ?? 'spot'}',
                ),
              ));
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _Lab.sky.withOpacity(0.6)),
              padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('🤖', style: TextStyle(fontSize: 15)),
          ),
        ]),
      ]),
    );
  }

  Widget _statePill(_Lab lab, String s) {
    final (c, txt) = switch (s) {
      'good' => (_Lab.emerald, 'GOOD'),
      'caution' => (_Lab.amber, 'CAUTION'),
      'danger' => (_Lab.rose, 'DANGER'),
      _ => (_Lab.slate, 'UNKNOWN'),
    };
    return _pill(lab, txt, c);
  }

  Widget _crowdBadge(_Lab lab, Map<String, dynamic> c) {
    final lv = '${c['level']}';
    final (col, key) = switch (lv) {
      'low' => (_Lab.emerald, 'vp_crowd_l'),
      'moderate' => (_Lab.amber, 'vp_crowd_m'),
      'high' => (_Lab.rose, 'vp_crowd_h'),
      _ => (_Lab.slate, 'vp_crowd_u'),
    };
    final parts = <String>['👥 ${key.tr()}'];
    final hrs = c['gfw_hours_30d'];
    if (hrs is num) parts.add('🚢 GFW ${hrs.toStringAsFixed(1)}h/30d');
    final n = c['community_recent'];
    if (n is num && n > 0) parts.add('${n.toInt()} ORCA pick(s)/24h');
    return _pill(lab, parts.join(' · '), col, fs: 9.8);
  }

  // ── STEP 3 · transit (mockup 4) ──────────────────────────────────
  Widget _transitView(_Lab lab) {
    final presets = <(String, Harbour?, Harbour?)>[
      ('Chennai → Kanyakumari', _matchHarbour('Chennai'),
          _matchHarbour('Kanyakumari')),
      ('Kochi → Lakshadweep', _matchHarbour('Kochi'),
          _matchHarbour('Lakshadweep')),
    ];
    final probe = widget.app.probePoint;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('vp_dest_t'.tr(),
          style: TextStyle(
              color: lab.white, fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      _pill(lab, '🚩 ${'vp_origin'.tr()}: $_startName', _Lab.tealBr),
      const SizedBox(height: 14),

      Text('${'vp_target'.tr()} ⚓',
          style: TextStyle(color: lab.body, fontSize: 12.5)),
      const SizedBox(height: 8),
      _harbourDrop(lab, _dHar, (h) => _setDest(h.lat, h.lon, h.name, h: h)),
      const SizedBox(height: 10),
      _outBtn(lab, Icons.map_rounded, 'vp_dest_map'.tr(), () {
        widget.app.jumpTab?.call(1);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('vp_hint_tap'.tr())));
      }),
      if (probe != null) ...[
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _setDest(probe.latitude, probe.longitude,
              '🗺️ ${probe.latitude.toStringAsFixed(3)}, ${probe.longitude.toStringAsFixed(3)}'),
          child: _pill(lab,
              '🗺️ ${'vp_use_tapped'.tr()} (${probe.latitude.toStringAsFixed(3)}, ${probe.longitude.toStringAsFixed(3)})',
              _Lab.sky),
        ),
      ],
      const SizedBox(height: 12),

      Row(children: [
        Expanded(child: _coordField(lab, _dLatC, '${'vp_lat'.tr()} 8.0883')),
        const SizedBox(width: 8),
        Expanded(child: _coordField(lab, _dLonC, '${'vp_lon'.tr()} 77.5385')),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _applyManualCoords(false),
          child: _pill(lab, 'vp_apply'.tr(), _Lab.sky),
        ),
      ]),
      if (_dLat != null) ...[
        const SizedBox(height: 8),
        _pill(lab, '🏁 $_destName', _Lab.emerald),
      ],
      const SizedBox(height: 16),

      Text('vp_presets'.tr(), style: TextStyle(color: lab.faint, fontSize: 11)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in presets)
          if (p.$2 != null && p.$3 != null)
            GestureDetector(
              onTap: () {
                _setStart(p.$2!.lat, p.$2!.lon, p.$2!.name, h: p.$2);
                _setDest(p.$3!.lat, p.$3!.lon, p.$3!.name, h: p.$3);
              },
              child: _pill(lab, p.$1, _Lab.slate, outline: true, fs: 11),
            ),
      ]),
      const SizedBox(height: 18),

      // AUTO-SAFETY PROTOCOL box (mockup 4)
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _Lab.sky.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Lab.sky.withOpacity(0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('vp_safety'.tr(),
              style: const TextStyle(
                  color: _Lab.sky,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          _safetyRow(lab, '📐', 'vp_s1'),
          _safetyRow(lab, '🌍', 'vp_s2'),
          _safetyRow(lab, '🌊', 'vp_s3'),
        ]),
      ),
      const SizedBox(height: 18),
      _bigBtn(_Lab.sky, 'vp_analyze'.tr(), _analyze, busy: _rtBusy),
    ]);
  }

  Widget _safetyRow(_Lab lab, String emoji, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(key.tr(),
                style: TextStyle(color: lab.body, fontSize: 12))),
      ]),
    );
  }
}
