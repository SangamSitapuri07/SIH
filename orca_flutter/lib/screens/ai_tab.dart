import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// (B1) AI tab — REAL 10-agent analysis. Backend `/api/v1/reason`
/// pehle se LIVE hai; UI sirf uska sach dikhata hai. Koi invented
/// confidence % nahi — asli coverage (kitne agents ke paas live data
/// tha) hi confidence ka honest measure hai.
class AiTab extends StatefulWidget {
  final Settings settings;
  final AppState app;
  const AiTab({super.key, required this.settings, required this.app});

  @override
  State<AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<AiTab> {
  Map<String, dynamic>? _out;
  Object? _err;
  bool _busy = false;
  double _lat = 20.9, _lon = 70.37; // default Veraval (home se parity)

  static const _agentIcon = <String, String>{
    'ocean': '🌊',
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

  Future<void> _run() async {
    final fix = widget.app.lastFix;
    if (fix != null) {
      _lat = fix.latitude;
      _lon = fix.longitude;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await OrcaApi.reason(widget.settings.base, _lat, _lon);
      if (!mounted) return;
      setState(() {
        _out = r;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e;
        _busy = false;
      });
    }
  }

  Color _riskColor(String? risk) {
    switch ((risk ?? '').toLowerCase()) {
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

  String _srcName(dynamic e) {
    if (e is Map) {
      return '${e['source'] ?? e['name'] ?? e['id'] ?? '?'}';
    }
    return '$e';
  }

  String _srcReason(dynamic e) {
    if (e is Map) return '${e['reason'] ?? e['error'] ?? ''}'.trim();
    return '';
  }

  Widget _card(BuildContext context, Widget child,
          {Color? border, Color? bg}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg ?? Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border ?? OrcaTheme.cardLine),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
      children: [
        Row(children: [
          Text('ai_heading'.tr(), style: t.titleLarge),
          const Spacer(),
          Text(
            'ai_point'.tr(args: [
              _lat.toStringAsFixed(3),
              _lon.toStringAsFixed(3)
            ]),
            style: t.bodySmall?.copyWith(color: OrcaTheme.subText),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.psychology_alt_rounded),
            label: Text(_busy ? 'ai_running'.tr() : 'ai_run_btn'.tr()),
            style: FilledButton.styleFrom(
              backgroundColor: OrcaTheme.teal,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_err != null)
          FetchError(detail: _err.toString(), onRetry: _run)
        else if (_out != null)
          ..._buildResult(context)
        else
          _card(
            context,
            Text(
              'ai_run_btn'.tr(),
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: OrcaTheme.subText),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildResult(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _out!;
    final risk = '${r['overall_risk'] ?? 'unknown'}';
    final cov =
        (r['data_coverage'] as Map?)?.cast<String, dynamic>() ?? const {};
    final used = (r['data_sources_used'] as List?) ?? const [];
    final failed = (r['data_sources_failed'] as List?) ?? const [];
    final agents = (r['agents'] as List?) ?? const [];
    final fetched = '${r['fetched_at'] ?? ''}';

    final list = <Widget>[];

    // ── overall risk banner ──
    final rc = _riskColor(risk);
    list.add(_card(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ai_overall'.tr(), style: t.bodySmall),
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.shield_rounded, color: rc, size: 26),
          const SizedBox(width: 8),
          Text(risk.toUpperCase(),
              style: t.headlineSmall?.copyWith(
                  color: rc, fontWeight: FontWeight.w800)),
        ]),
      ]),
      border: rc,
      bg: rc.withOpacity(0.08),
    ));

    // ── recommendation ──
    final reco = '${r['recommendation'] ?? ''}';
    if (reco.isNotEmpty) {
      list.add(_card(
        context,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ai_reco'.tr(),
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(reco, style: t.bodyLarge),
        ]),
      ));
    }

    // ── coverage + fetched (honesty strip) ──
    list.add(Wrap(spacing: 8, runSpacing: 8, children: [
      if (cov['known'] != null && cov['total'] != null)
        Chip(
          avatar: const Icon(Icons.sensors_rounded, size: 16),
          label: Text('ai_coverage'.tr(args: [
            '${cov['known']}',
            '${cov['total']}'
          ])),
          backgroundColor: OrcaTheme.mintChip,
        ),
      if (fetched.isNotEmpty)
        Chip(
          avatar: const Icon(Icons.schedule_rounded, size: 16),
          label: Text('ai_fetched'
              .tr(args: [fetched.substring(0, 16).replaceAll('T', ' ')])),
        ),
    ]));

    // ── agent report cards ──
    list.add(const SizedBox(height: 6));
    list.add(Text('ai_agents'.tr(),
        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)));
    for (final a in agents.cast<Map>()) {
      final id = '${a['agent'] ?? a['id'] ?? '?'}';
      final summary = '${a['summary'] ?? ''}';
      final verdict = '${a['verdict'] ?? ''}';
      list.add(_card(
        context,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_agentIcon[id] ?? '🤖', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Expanded(
                child: Text(_prettyId(id),
                    style: t.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800))),
            if (verdict.isNotEmpty && verdict != 'null')
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: OrcaTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(verdict.replaceAll('_', ' '),
                    style: t.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
          ]),
          if (summary.isNotEmpty && summary != 'null') ...[
            const SizedBox(height: 6),
            Text(summary, style: t.bodyMedium),
          ],
        ]),
      ));
    }

    // ── sources honesty ──
    if (used.isNotEmpty) {
      list.add(const SizedBox(height: 6));
      list.add(Text('ai_sources_ok'.tr(),
          style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)));
      list.add(const SizedBox(height: 4));
      list.add(Wrap(
          spacing: 6,
          runSpacing: 6,
          children: used
              .map((e) => Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_srcName(e), style: t.bodySmall),
                  backgroundColor: OrcaTheme.mintChip))
              .toList()));
    }
    if (failed.isNotEmpty) {
      list.add(const SizedBox(height: 6));
      list.add(Text('ai_sources_fail'.tr(),
          style: t.titleSmall?.copyWith(
              fontWeight: FontWeight.w800, color: OrcaTheme.dangerRed)));
      list.add(const SizedBox(height: 4));
      for (final e in failed) {
        list.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '✖ ${_srcName(e)}${_srcReason(e).isNotEmpty ? ': ${_srcReason(e)}' : ''}',
            style: t.bodySmall?.copyWith(color: OrcaTheme.dangerRed),
          ),
        ));
      }
    }
    return list;
  }
}
