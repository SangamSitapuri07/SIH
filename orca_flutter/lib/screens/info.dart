import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart' show mlLang;

class InfoScreen extends StatefulWidget {
  final Settings settings;
  final AppState app;
  const InfoScreen({super.key, required this.settings, required this.app});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  late final TextEditingController _baseCtrl;
  String _conn = '', _connDetail = '';
  // translator states: '' | 'downloading' | 'ready' | 'fail' | 'unsupported'
  String _trState = '', _trOut = '';

  @override
  void initState() {
    super.initState();
    _baseCtrl = TextEditingController(text: widget.settings.base);
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _conn = 'checking';
      _connDetail = '';
    });
    try {
      final h = await OrcaApi.health(_baseCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _conn = 'ok';
        _connDetail =
            '${h['commit'] ?? h['version'] ?? ''}'.trim();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _conn = 'fail';
        _connDetail = '$e'; // honest reason
      });
    }
  }

  /// REAL ML Kit offline model download + demo translate. Koi fake nahi.
  Future<void> _translator() async {
    final target = mlLang(context.locale.languageCode);
    if (target == null || context.locale.languageCode == 'kok') {
      setState(() => _trState = 'unsupported');
      return;
    }
    setState(() {
      _trState = 'downloading';
      _trOut = '';
    });
    try {
      final mgr = OnDeviceTranslatorModelManager();
      final dl =
          await mgr.downloadModel(target.bcpCode, isWifiRequired: false);
      if (!dl) throw Exception('model download failed');
      final tr = OnDeviceTranslator(
          sourceLanguage: TranslateLanguage.english, targetLanguage: target);
      final out = await tr.translateText('Waves 1.2 m — conditions look safe.');
      tr.close();
      if (!mounted) return;
      setState(() {
        _trState = 'ready';
        _trOut = out;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trState = 'fail';
        _trOut = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = widget.settings;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('info_title'.tr(), style: t.textTheme.titleLarge),
      const SizedBox(height: 14),

      // ── भाषा ──
      OrcaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('language_lbl'.tr(),
              style: t.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final l in LangRef.langs)
              _langChip(t, l, context.locale == l.locale),
          ]),
          const SizedBox(height: 8),
          Text('feedback_note'.tr(),
              style: t.textTheme.bodyMedium?.copyWith(
                  fontSize: 11.5, color: t.colorScheme.secondary)),
        ]),
      ),

      // ── Display mode ──
      OrcaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('display_mode'.tr(),
              style: t.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(children: [
            _modeBtn(t, s, 0, Icons.light_mode_rounded, 'mode_light'.tr()),
            const SizedBox(width: 8),
            _modeBtn(t, s, 1, Icons.dark_mode_rounded, 'mode_dark'.tr()),
            const SizedBox(width: 8),
            _modeBtn(t, s, 2, Icons.wb_sunny_rounded, 'mode_dhoop'.tr()),
          ]),
        ]),
      ),

      // ── Text size ──
      OrcaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('text_size'.tr(),
                style: t.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${(s.scale * 100).round()}%',
                style: t.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: t.colorScheme.secondary,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _zoomBtn(t, Icons.remove_rounded, () => s.zoom(false)),
            Expanded(
              child: Center(
                  child: Text('preview'.tr(),
                      style: t.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600))),
            ),
            _zoomBtn(t, Icons.add_rounded, () => s.zoom(true)),
          ]),
        ]),
      ),

      // ── Offline translator (REAL ML Kit) ──
      OrcaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('translator_title'.tr(),
              style: t.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('translator_desc'.tr(),
              style: t.textTheme.bodyMedium?.copyWith(
                  fontSize: 12.5, color: t.colorScheme.secondary)),
          const SizedBox(height: 10),
          if (_trState == 'unsupported')
            Text('translate_unsupported'.tr(),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: OrcaTheme.warnAmber))
          else if (_trState == 'ready') ...[
            Row(children: [
              const Icon(Icons.check_circle,
                  size: 15, color: OrcaTheme.okGreen),
              const SizedBox(width: 5),
              Text('model_ready'.tr(),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: OrcaTheme.okGreen)),
            ]),
            if (_trOut.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('e.g. "Waves 1.2 m…" → $_trOut',
                    style: t.textTheme.bodyMedium?.copyWith(
                        fontSize: 12, fontStyle: FontStyle.italic)),
              ),
          ] else
            OutlinedButton.icon(
              onPressed: _trState == 'downloading' ? null : _translator,
              icon: _trState == 'downloading'
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded, size: 16),
              label: Text('model_download'.tr()),
            ),
          if (_trState == 'fail')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_trOut,
                  style: const TextStyle(
                      fontSize: 11, color: OrcaTheme.dangerRed)),
            ),
        ]),
      ),

      // ── Backend connection ──
      OrcaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('backend_title'.tr(),
              style: t.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: _baseCtrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'backend_hint'.tr(),
              isDense: true,
              filled: true,
              fillColor:
                  t.colorScheme.surfaceContainerHighest.withOpacity(0.35),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.dividerColor)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.dividerColor)),
            ),
            onSubmitted: (v) => s.setBase(v),
          ),
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () {
                s.setBase(_baseCtrl.text);
                _check();
              },
              icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
              label: Text('check'.tr()),
            ),
            const SizedBox(width: 10),
            if (_conn == 'checking')
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (_conn == 'ok') ...[
              const Icon(Icons.check_circle,
                  size: 16, color: OrcaTheme.okGreen),
              const SizedBox(width: 4),
              Flexible(
                child: Text('${'conn_ok'.tr()} $_connDetail',
                    style: const TextStyle(
                        fontSize: 12,
                        color: OrcaTheme.okGreen,
                        fontWeight: FontWeight.w700)),
              ),
            ] else if (_conn == 'fail') ...[
              const Icon(Icons.cancel,
                  size: 16, color: OrcaTheme.dangerRed),
              const SizedBox(width: 4),
              Flexible(
                child: Text('${'conn_fail'.tr()} — $_connDetail',
                    style: const TextStyle(
                        fontSize: 11.5, color: OrcaTheme.dangerRed)),
              ),
            ],
          ]),
        ]),
      ),

      // ── ईमानदारी Charter ──
      OrcaCard(
        border: OrcaTheme.warnAmber.withOpacity(0.5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('honesty_title'.tr(),
              style: t.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _honest(t, Icons.verified_user_rounded, 'honest_1'.tr()),
          _honest(t, Icons.schedule_rounded, 'honest_2'.tr()),
          _honest(t, Icons.error_outline_rounded, 'honest_3'.tr()),
          _honest(t, Icons.route_rounded, 'honest_4'.tr()),
        ]),
      ),

      Center(
        child: Text('version_line'.tr(),
            style: t.textTheme.bodyMedium?.copyWith(
                fontSize: 11, color: t.colorScheme.secondary)),
      ),
      const SizedBox(height: 8),
    ]);
  }

  Widget _langChip(ThemeData t, ({Locale locale, String native, String eng}) l,
      bool sel) {
    return GestureDetector(
      onTap: () => context.setLocale(l.locale),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? t.colorScheme.primary : t.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? t.colorScheme.primary : t.dividerColor,
              width: sel ? 2 : 1),
        ),
        child: Text(l.native,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                color: sel ? Colors.white : t.colorScheme.onSurface)),
      ),
    );
  }

  Widget _modeBtn(
      ThemeData t, Settings s, int m, IconData icon, String label) {
    final sel = s.mode == m;
    return Expanded(
      child: GestureDetector(
        onTap: () => s.setMode(m),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: sel ? t.colorScheme.primary : t.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: sel ? t.colorScheme.primary : t.dividerColor,
                width: sel ? 2 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 16,
                color: sel ? Colors.white : t.colorScheme.secondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                      color: sel ? Colors.white : t.colorScheme.onSurface)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _zoomBtn(ThemeData t, IconData icon, VoidCallback onTap) =>
      InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.dividerColor)),
          child: Icon(icon, size: 20, color: t.colorScheme.secondary),
        ),
      );

  Widget _honest(ThemeData t, IconData icon, String txt) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: t.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(txt,
                  style: t.textTheme.bodyMedium?.copyWith(fontSize: 13.5))),
        ]),
      );
}
