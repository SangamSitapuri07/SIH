import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// GPS helper — throws StateError('gps_off') / ('gps_denied') honestly.
Future<Position> orcaFix() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw StateError('gps_off');
  }
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.denied ||
      p == LocationPermission.deniedForever) {
    throw StateError('gps_denied');
  }
  return Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 12));
}

class HomeScreen extends StatefulWidget {
  final Settings settings;
  final AppState app;
  const HomeScreen({super.key, required this.settings, required this.app});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _defaultLat = 20.9, _defaultLon = 70.37; // Veraval
  double _lat = _defaultLat, _lon = _defaultLon;
  bool _usingGps = false, _gpsPending = true;
  Map<String, dynamic>? _adv;
  String? _err;
  bool _loading = true, _fromCache = false;
  DateTime? _cachedAt;
  String? _translated;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _restoreCache();
    await _tryGps();
    await _load();
  }

  Future<void> _restoreCache() async {
    final p = await SharedPreferences.getInstance();
    if (!_usingGps) {
      _lat = p.getDouble('orca_lat') ?? _defaultLat;
      _lon = p.getDouble('orca_lon') ?? _defaultLon;
      setState(() {});
    }
  }

  Future<void> _tryGps() async {
    try {
      final fix = await orcaFix();
      widget.app.setFix(fix);
      _lat = fix.latitude;
      _lon = fix.longitude;
      _usingGps = true;
      final p = await SharedPreferences.getInstance();
      await p.setDouble('orca_lat', _lat);
      await p.setDouble('orca_lon', _lon);
    } on StateError {
      // honest: chip shows loc_unknown / loc_default
    } catch (_) {} finally {
      _gpsPending = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _err = null;
      _fromCache = false;
    });
    try {
      final data = await OrcaApi.advisory(widget.settings.base, _lat, _lon);
      final p = await SharedPreferences.getInstance();
      await p.setString(
          'pack_adv',
          jsonEncode({
            'ts': DateTime.now().toIso8601String(),
            'lat': _lat,
            'lon': _lon,
            'data': data
          }));
      if (mounted) {
        setState(() {
          _adv = data;
          _loading = false;
          _translated = null;
        });
      }
    } catch (e) {
      // offline pack fallback — honest banner, kabhi invent nahi
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('pack_adv');
      if (raw != null) {
        try {
          final pack = jsonDecode(raw) as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _adv = pack['data'] as Map<String, dynamic>;
              _fromCache = true;
              _cachedAt = DateTime.tryParse('${pack['ts']}');
              _loading = false;
            });
          }
          return;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _err = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _manualLocation() async {
    final laCtrl = TextEditingController(text: _lat.toStringAsFixed(4));
    final loCtrl = TextEditingController(text: _lon.toStringAsFixed(4));
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('manual_loc'.tr()),
        content: Row(children: [
          Expanded(
              child: TextField(
                  controller: laCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Lat'))),
          const SizedBox(width: 10),
          Expanded(
              child: TextField(
                  controller: loCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: true),
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
      final la = double.tryParse(laCtrl.text.trim());
      final lo = double.tryParse(loCtrl.text.trim());
      if (la != null && lo != null && la.abs() <= 90 && lo.abs() <= 180) {
        _lat = la;
        _lon = lo;
        _usingGps = false;
        final p = await SharedPreferences.getInstance();
        await p.setDouble('orca_lat', la);
        await p.setDouble('orca_lon', lo);
        await _load();
      }
    }
  }

  Future<void> _reloadGps() async {
    setState(() => _gpsPending = true);
    await _tryGps();
    await _load();
  }

  Future<void> _translate() async {
    final adv = _adv;
    if (adv == null) return;
    final target = TranslateLanguage.fromBcp(context.locale.languageCode);
    final src = (adv['plain_en'] as List?)?.join('\n') ?? '';
    if (target == null || src.isEmpty) return;
    try {
      final tr = OnDeviceTranslator(
          sourceLanguage: TranslateLanguage.english, targetLanguage: target);
      final out = await tr.translateText(src);
      tr.close();
      if (mounted) setState(() => _translated = out);
    } catch (e) {
      if (mounted) setState(() => _translated = '— ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final adv = _adv;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        // ── greeting + avatar ──
        Text('greeting_morning'.tr(),
            style: t.textTheme.bodyMedium
                ?.copyWith(color: t.colorScheme.secondary, fontSize: 13)),
        const SizedBox(height: 6),
        // ── मेरी जगह chip (और manual picker) ──
        GestureDetector(
          onTap: _manualLocation,
          child: Row(children: [
            Icon(Icons.my_location_rounded,
                size: 14,
                color: _usingGps ? OrcaTheme.okGreen : t.colorScheme.secondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _gpsPending
                    ? 'gps_getting'.tr()
                    : _usingGps
                        ? '${'my_location'.tr()}: ${_lat.toStringAsFixed(3)}°N ${_lon.toStringAsFixed(3)}°E'
                        : (_lat == _defaultLat && _lon == _defaultLon
                            ? 'loc_default'.tr()
                            : '${_lat.toStringAsFixed(3)}°N ${_lon.toStringAsFixed(3)}°E'),
                style: t.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: _usingGps
                        ? OrcaTheme.okGreen
                        : t.colorScheme.secondary,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.edit_location_alt_rounded,
                size: 16, color: t.colorScheme.secondary),
          ]),
        ),
        const SizedBox(height: 14),

        if (_loading)
          const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()))
        else if (_err != null)
          FetchError(detail: _err!, onRetry: _load)
        else if (adv != null) ...[
          if (_fromCache)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: OrcaTheme.dangerRed.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: OrcaTheme.dangerRed.withOpacity(0.4))),
              child: Text(
                  'data_from_cache'.tr(args: [
                    _cachedAt != null
                        ? DateFormat('dd MMM, hh:mm a').format(_cachedAt!)
                        : '—'
                  ]),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: OrcaTheme.dangerRed)),
            ),
          _VerdictCard(adv: adv, translated: _translated),
          _buildTranslateBtn(t),
          _MetricTiles(vars: adv['variables'] as Map? ?? const {}),
          _Chart48(chart: adv['hourly_chart'] as Map?),
          _SourcesChips(adv: adv),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 20),
            child: Text('${adv['disclaimer'] ?? ''}',
                style: t.textTheme.bodyMedium?.copyWith(
                    fontSize: 10.5, color: t.colorScheme.secondary)),
          ),
        ],
      ]),
    );
  }

  Widget _buildTranslateBtn(ThemeData t) {
    final target = TranslateLanguage.fromBcp(context.locale.languageCode);
    if (target == null || context.locale.languageCode == 'en') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _translate,
          icon: const Icon(Icons.translate_rounded, size: 17),
          label: const Text('Translate'),
        ),
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final Map<String, dynamic> adv;
  final String? translated;
  const _VerdictCard({required this.adv, this.translated});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = switch ('${adv['color']}') {
      'green' => OrcaTheme.okGreen,
      'red' => OrcaTheme.dangerRed,
      _ => OrcaTheme.warnAmber,
    };
    final isHi = context.locale.languageCode != 'en';
    final headline =
        isHi ? '${adv['headline_hi'] ?? adv['headline']}' : '${adv['headline']}';
    final plains = ((isHi ? adv['plain_hi'] : adv['plain_en']) as List?)
            ?.map((e) => '$e')
            .toList() ??
        const <String>[];
    return OrcaCard(
      bg: color.withOpacity(0.08),
      border: color.withOpacity(0.6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('verdict_title'.tr(),
            style: t.textTheme.bodyMedium
                ?.copyWith(fontSize: 13, color: t.colorScheme.secondary)),
        const SizedBox(height: 4),
        Text('${adv['icon'] ?? ''} $headline',
            style: t.textTheme.titleLarge
                ?.copyWith(fontSize: 24, color: color)),
        const SizedBox(height: 10),
        for (final s in plains)
          Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(s,
                  style: t.textTheme.bodyMedium?.copyWith(fontSize: 13.5))),
        if (translated != null) ...[
          Divider(color: t.dividerColor),
          Text(translated!,
              style: t.textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5, fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }
}

class _MetricTiles extends StatelessWidget {
  final Map vars;
  const _MetricTiles({required this.vars});

  String _v(dynamic x, String unit, [int dp = 1]) =>
      x is num ? '${x.toStringAsFixed(dp)} $unit' : '—';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tiles = <(String, String, Color)>[
      ('waves_lbl'.tr(), _v(vars['wave_height_m'], 'm'), OrcaTheme.teal),
      ('wind_lbl'.tr(), _v(vars['wind_kts'], 'kn', 0), OrcaTheme.tealDeep),
      ('gust_lbl'.tr(), _v(vars['gust_kts'], 'kn', 0), OrcaTheme.warnAmber),
      ('sst_lbl'.tr(), _v(vars['sst_c'], '°C'), const Color(0xFFF97316)),
      ('current_lbl'.tr(), _v(vars['current_kn'], 'kn', 2), OrcaTheme.okGreen),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        for (final (lbl, val, c) in tiles)
          Container(
            decoration: BoxDecoration(
              color: t.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.dividerColor),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lbl,
                  style: t.textTheme.bodyMedium?.copyWith(
                      fontSize: 10.5, color: t.colorScheme.secondary)),
              const Spacer(),
              Text(val,
                  style: t.textTheme.titleLarge
                      ?.copyWith(fontSize: 17, color: c)),
            ]),
          ),
      ],
    );
  }
}

class _Chart48 extends StatelessWidget {
  final Map? chart;
  const _Chart48({this.chart});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (chart == null) return const SizedBox.shrink();
    List<double?> col(String k) =>
        ((chart![k] as List?) ?? []).map((e) => (e as num?)?.toDouble()).toList();
    final wave = col('wave_m'), wind = col('wind_kn');
    List<FlSpot> spots(List<double?> xs) => [
          for (var i = 0; i < xs.length; i++)
            if (xs[i] != null) FlSpot(i.toDouble(), xs[i]!)
        ];
    if (spots(wave).isEmpty && spots(wind).isEmpty) {
      return const SizedBox.shrink();
    }
    return OrcaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('forecast48'.tr(),
            style: t.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: LineChart(LineChartData(
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 6,
                  getTitlesWidget: (v, _) {
                    final labels = (chart!['labels'] as List?) ?? [];
                    final i = v.toInt();
                    if (i < 0 || i >= labels.length) {
                      return const SizedBox.shrink();
                    }
                    final s = '${labels[i]}'; // "MM-DDTHH:MM"
                    final hh = s.length >= 13 ? s.substring(11, 13) : s;
                    return Text('${hh}h',
                        style: TextStyle(
                            fontSize: 9, color: t.colorScheme.secondary));
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(0),
                        style: TextStyle(
                            fontSize: 9, color: t.colorScheme.secondary))),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots(wave),
                isCurved: true,
                color: OrcaTheme.teal,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                    show: true, color: OrcaTheme.teal.withOpacity(0.10)),
              ),
              LineChartBarData(
                spots: spots(wind),
                isCurved: true,
                color: OrcaTheme.warnAmber,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
            ],
          )),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _Dot(OrcaTheme.teal),
          Text(' ${'waves_lbl'.tr()} (m)   ',
              style: const TextStyle(fontSize: 11)),
          _Dot(OrcaTheme.warnAmber),
          Text(' ${'wind_lbl'.tr()} (kn)', style: const TextStyle(fontSize: 11)),
        ]),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color c;
  const _Dot(this.c);
  @override
  Widget build(BuildContext context) => Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

class _SourcesChips extends StatelessWidget {
  final Map<String, dynamic> adv;
  const _SourcesChips({required this.adv});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ok = (adv['sources'] as List?) ?? const [];
    final failed = (adv['sources_failed'] as List?) ?? const [];
    return OrcaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('sources_lbl'.tr(),
            style: t.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in ok) _chip('$s', OrcaTheme.okGreen),
          // honest: failed sources hamesha RED ke saath dikhte hain
          for (final s in failed) _chip('$s', OrcaTheme.dangerRed),
        ]),
      ]),
    );
  }

  Widget _chip(String s, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.withOpacity(0.6))),
        child: Text(s,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
      );
}
