import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart' show FetchError;

/// (B17) POINT ANALYSIS — "map pe click → us point ka poora haal".
///
/// User demand: web ke HOME panel jaisa — "ai vala + click krne par
/// vaha ka environment bhi dikhne vala". Ye screen DO real endpoints
/// parallel chalati hai:
///   1) /api/v1/advisory → LIVE ENVIRONMENT: verdict/headline + full
///      variables grid (waves/swell/wind/gust/SST/current/chl/PFZ/
///      cyclone) + 48h outlook + reasons + sources honesty
///   2) /api/v1/reason  → 10-AGENT AI ANALYSIS: overall risk banner +
///      recommendation + per-agent verdict cards + sources honesty.
///
/// Entry: map long-press sheet 🤖, hotspot sheet 🤖, voyage reco card 🤖.
/// Koi dummy number yahan bhi nahi — fail hua section apna honest
/// reason dikhata hai, doosra section zinda rehta hai.
class PointAnalysisScreen extends StatefulWidget {
  final Settings settings;
  final AppState app;
  final double lat;
  final double lon;
  final String name;

  const PointAnalysisScreen({
    super.key,
    required this.settings,
    required this.app,
    required this.lat,
    required this.lon,
    this.name = '',
  });

  @override
  State<PointAnalysisScreen> createState() => _PointAnalysisScreenState();
}

class _PointAnalysisScreenState extends State<PointAnalysisScreen> {
  Map<String, dynamic>? _adv;
  Object? _advErr;
  bool _advBusy = true;
  Map<String, dynamic>? _res;
  Object? _resErr;
  bool _resBusy = true;

  static const _agentIcon = <String, String>{
    'satellite': '🛰️',
    'weather': '🌦️',
    'gis': '🗺️',
    'marine_ecology': '🐟',
    'fisheries': '🎣',
    'marine_risk': '🚨',
    'anomaly': '🔍',
    'validation': '✅',
    'validation_qc': '✅',
    'orca_reasoning': '🧠',
  };

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _advBusy = true;
      _resBusy = true;
      _advErr = null;
      _resErr = null;
    });
    OrcaApi.advisory(widget.settings.base, widget.lat, widget.lon).then((a) {
      if (!mounted) return;
      setState(() {
        _adv = a;
        _advBusy = false;
      });
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _advErr = e;
        _advBusy = false;
      });
    });
    OrcaApi.reason(widget.settings.base, widget.lat, widget.lon).then((r) {
      if (!mounted) return;
      setState(() {
        _res = r;
        _resBusy = false;
      });
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _resErr = e;
        _resBusy = false;
      });
    });
  }

  // ── helpers ──────────────────────────────────────────────────────
  String _f(dynamic v, [int dp = 1]) => v is num ? v.toStringAsFixed(dp) : '—';

  Color _riskColor(String risk) {
    switch (risk.toLowerCase()) {
      case 'low':
        return OrcaTheme.okGreen;
      case 'moderate':
        return OrcaTheme.warnAmber;
      case 'high':
        return const Color(0xFFF97316);
      case 'critical':
        return OrcaTheme.dangerRed;
      default:
        return OrcaTheme.subText;
    }
  }

  String _prettyId(String id) =>
      id.replaceAll('_', ' ').split(' ').map((w) {
        return w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);
      }).join(' ');

  String _srcName(dynamic e) =>
      e is Map ? '${e['source'] ?? e['name'] ?? e['id'] ?? '?'}' : '$e';

  String _srcReason(dynamic e) =>
      e is Map ? '${e['reason'] ?? e['error'] ?? ''}'.trim() : '';

  Widget _card(ThemeData t, Widget child, {Color? border, Color? bg}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: bg ?? t.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border ?? t.dividerColor),
        ),
        child: child,
      );

  Widget _secTitle(TextTheme tt, IconData ic, String key) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          Icon(ic, size: 16, color: OrcaTheme.teal),
          const SizedBox(width: 6),
          Text(key.tr(),
              style:
                  tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _busyCard(ThemeData t) => _card(
        t,
        Row(children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(
              child: Text('vp_loading'.tr(), style: t.textTheme.bodySmall)),
        ]),
      );

  // ── SECTION 1 · live environment (advisory) ──────────────────────
  Widget _envSection(ThemeData t) {
    final tt = t.textTheme;
    if (_advBusy) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _secTitle(tt, Icons.waves_rounded, 'pa_env'),
        _busyCard(t),
      ]);
    }
    if (_advErr != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _secTitle(tt, Icons.waves_rounded, 'pa_env'),
        _card(
          t,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('pa_env_fail'.tr(),
                style: tt.titleSmall?.copyWith(
                    color: OrcaTheme.dangerRed, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('$_advErr',
                style: tt.bodySmall?.copyWith(fontSize: 10)),
            const SizedBox(height: 8),
            FetchError(detail: '', onRetry: _run),
          ]),
        ),
      ]);
    }
    final a = _adv!;
    final v = (a['variables'] as Map?) ?? const {};
    final verdict = '${a['verdict']}';
    final vc = verdict == 'no_go'
        ? OrcaTheme.dangerRed
        : verdict == 'caution'
            ? OrcaTheme.warnAmber
            : OrcaTheme.okGreen;
    final n48 = (a['outlook_48h'] as Map?) ?? const {};
    final reasons = (a['reasons'] as List?) ?? const [];
    final srcFail = (a['sources_failed'] as List?) ?? const [];
    final sw = (a['safe_window'] as Map?);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _secTitle(tt, Icons.waves_rounded, 'pa_env'),
      _card(
        t,
        border: vc,
        bg: vc.withOpacity(0.06),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${a['icon'] ?? ''}', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${a['headline'] ?? verdict.toUpperCase()}',
                  style: tt.titleSmall
                      ?.copyWith(color: vc, fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 6, children: [
            Text('🌊 ${_f(v['wave_height_m'])} m · swell ${_f(v['swell_m'])} m',
                style: tt.bodySmall),
            Text('💨 ${_f(v['wind_kts'], 0)} kn · gust ${_f(v['gust_kts'], 0)} kn',
                style: tt.bodySmall),
            Text(
                '🌡 ${_f(v['sst_c'])} °C${v['sst_source'] != null ? ' (${v['sst_source']})' : ''}',
                style: tt.bodySmall),
            Text('🌀 ${_f(v['current_kn'])} kn ${v['current_dir'] ?? ''}',
                style: tt.bodySmall),
            Text('🦠 chl ${_f(v['chlorophyll_mg_m3'])} mg/m³',
                style: tt.bodySmall),
            if (v['nearest_pfz_nm'] != null)
              Text(
                  '🎣 PFZ ${_f(v['nearest_pfz_nm'])} NM ${v['nearest_pfz_bearing'] ?? ''}',
                  style: tt.bodySmall),
          ]),
          if (v['cyclone_note'] != null && '${v['cyclone_note']}' != 'null')
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text('🌀 ${v['cyclone_note']}',
                  style: tt.bodySmall?.copyWith(
                      color: OrcaTheme.warnAmber,
                      fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 8),
          Text(
              '↗48h: 🌊 ${_f(n48['wave_max_m'])} m · 💨 ${_f(n48['wind_max_kn'], 0)} kn · gust ${_f(n48['gust_max_kn'], 0)} kn',
              style: tt.bodySmall?.copyWith(
                  fontSize: 10.5, color: t.colorScheme.secondary)),
          if (sw != null && sw['found'] == true && sw['note'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('⏱ ${sw['note']}',
                  style: tt.bodySmall?.copyWith(
                      color: OrcaTheme.okGreen, fontSize: 11)),
            ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final r in reasons)
              Text('· $r',
                  style: tt.bodySmall?.copyWith(
                      fontSize: 10.5, color: t.colorScheme.secondary)),
          ],
          for (final s in srcFail)
            Text('✘ $s',
                style: tt.bodySmall?.copyWith(
                    fontSize: 10, color: OrcaTheme.dangerRed)),
          if (a['disclaimer'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${a['disclaimer']}',
                  style: tt.bodySmall?.copyWith(
                      fontSize: 9, color: t.colorScheme.secondary)),
            ),
        ]),
      ),
    ]);
  }

  // ── SECTION 2 · 10-agent AI analysis (reason) ────────────────────
  Widget _reasonSection(ThemeData t) {
    final tt = t.textTheme;
    if (_resBusy) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _secTitle(tt, Icons.psychology_alt_rounded, 'pa_ai_hdr'),
        _busyCard(t),
      ]);
    }
    if (_resErr != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _secTitle(tt, Icons.psychology_alt_rounded, 'pa_ai_hdr'),
        _card(
          t,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('pa_env_fail'.tr(),
                style: tt.titleSmall?.copyWith(
                    color: OrcaTheme.dangerRed, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('$_resErr',
                style: tt.bodySmall?.copyWith(fontSize: 10)),
            const SizedBox(height: 8),
            FetchError(detail: '', onRetry: _run),
          ]),
        ),
      ]);
    }
    final r = _res!;
    final risk = '${r['overall_risk'] ?? 'unknown'}';
    final rc = _riskColor(risk);
    final cov =
        (r['data_coverage'] as Map?)?.cast<String, dynamic>() ?? const {};
    final used = (r['data_sources_used'] as List?) ?? const [];
    final failed = (r['data_sources_failed'] as List?) ?? const [];
    final agents = (r['agents'] as List?) ?? const [];
    final fetched = '${r['fetched_at'] ?? ''}';
    final reco = '${r['recommendation'] ?? ''}';
    final summary = '${r['summary'] ?? ''}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _secTitle(tt, Icons.psychology_alt_rounded, 'pa_ai_hdr'),

      // overall risk banner
      _card(
        t,
        border: rc,
        bg: rc.withOpacity(0.08),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ai_overall'.tr(), style: tt.bodySmall),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.shield_rounded, color: rc, size: 26),
            const SizedBox(width: 8),
            Text(risk.toUpperCase(),
                style: tt.headlineSmall
                    ?.copyWith(color: rc, fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),

      // recommendation + summary
      if (reco.isNotEmpty && reco != 'null')
        _card(
          t,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ai_reco'.tr(),
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(reco, style: tt.bodyLarge?.copyWith(fontSize: 14)),
            if (summary.isNotEmpty && summary != 'null') ...[
              const SizedBox(height: 6),
              Text(summary,
                  style: tt.bodySmall?.copyWith(
                      color: t.colorScheme.secondary, height: 1.45)),
            ],
          ]),
        ),

      // honesty chips
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (cov['known'] != null && cov['total'] != null)
          Chip(
            avatar: const Icon(Icons.sensors_rounded, size: 16),
            label: Text('ai_coverage'
                .tr(args: ['${cov['known']}', '${cov['total']}'])),
            backgroundColor: OrcaTheme.mintChip,
          ),
        if (fetched.length >= 16)
          Chip(
            avatar: const Icon(Icons.schedule_rounded, size: 16),
            label: Text(
                'ai_fetched'.tr(args: [fetched.substring(0, 16).replaceAll('T', ' ')])),
          ),
      ]),

      // agent cards
      const SizedBox(height: 8),
      Text('ai_agents'.tr(),
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      for (final a in agents.cast<Map>())
        _card(
          t,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(_agentIcon['${a['agent'] ?? a['id'] ?? '?'}'] ?? '🤖',
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_prettyId('${a['agent'] ?? a['id'] ?? '?'}'),
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if ('${a['verdict'] ?? ''}'.isNotEmpty &&
                  '${a['verdict'] ?? ''}' != 'null')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: OrcaTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${a['verdict']}'.replaceAll('_', ' '),
                      style:
                          tt.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
            ]),
            if ('${a['summary'] ?? ''}'.isNotEmpty &&
                '${a['summary'] ?? ''}' != 'null') ...[
              const SizedBox(height: 6),
              Text('${a['summary']}', style: tt.bodyMedium),
            ],
          ]),
        ),

      // sources honesty
      if (used.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('ai_sources_ok'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: used
              .map((e) => Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_srcName(e), style: tt.bodySmall),
                  backgroundColor: OrcaTheme.mintChip))
              .toList(),
        ),
      ],
      if (failed.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('ai_sources_fail'.tr(),
            style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w800, color: OrcaTheme.dangerRed)),
        const SizedBox(height: 4),
        for (final e in failed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '✖ ${_srcName(e)}${_srcReason(e).isNotEmpty ? ': ${_srcReason(e)}' : ''}',
              style: tt.bodySmall?.copyWith(color: OrcaTheme.dangerRed),
            ),
          ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final place = widget.name.isNotEmpty
        ? widget.name
        : '📍 ${widget.lat.toStringAsFixed(3)}, ${widget.lon.toStringAsFixed(3)}';
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('pa_title'.tr(),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(
              '$place · ${widget.lat.toStringAsFixed(3)}, ${widget.lon.toStringAsFixed(3)}',
              style: const TextStyle(fontSize: 10.5)),
        ]),
        actions: [
          IconButton(
            onPressed: (_advBusy || _resBusy) ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
        children: [
          _envSection(t),
          const SizedBox(height: 14),
          _reasonSection(t),
        ],
      ),
    );
  }
}
