import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/harbours.dart';
import '../marine.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart' show orcaFix;

class SosScreen extends StatefulWidget {
  final Settings settings;
  final AppState app;
  const SosScreen({super.key, required this.settings, required this.app});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  Position? _fix;
  String? _gpsErr;
  String _smsState = ''; // '', 'sent', 'fail'
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fix = widget.app.lastFix;
    _loadContact();
    if (_fix == null) _refresh();
  }

  Future<void> _loadContact() async {
    final p = await SharedPreferences.getInstance();
    _nameCtrl.text = p.getString('orca_sos_name') ?? '';
    _phoneCtrl.text = p.getString('orca_sos_phone') ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _saveContact() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('orca_sos_name', _nameCtrl.text.trim());
    await p.setString('orca_sos_phone', _phoneCtrl.text.trim());
    setState(() {});
  }

  Future<void> _refresh() async {
    setState(() {
      _gpsErr = null;
    });
    try {
      final f = await orcaFix();
      widget.app.setFix(f);
      if (mounted) setState(() => _fix = f);
    } on StateError catch (e) {
      if (mounted) setState(() => _gpsErr = e.message);
    } catch (e) {
      if (mounted) setState(() => _gpsErr = '$e');
    }
  }

  String get _posText {
    final f = _fix;
    if (f == null) return _gpsErr != null ? _gpsErr!.tr() : '…';
    String fmt(double v, String pos, String neg) {
      final a = v.abs();
      final d = a.floor();
      final m = ((a - d) * 60);
      return "$d°${m.toStringAsFixed(1)}'${v >= 0 ? pos : neg}";
    }

    return '${fmt(f.latitude, 'N', 'S')}  ${fmt(f.longitude, 'E', 'W')}';
  }

  String get _smsBody {
    final f = _fix;
    final time = DateFormat('dd MMM, hh:mm a').format(DateTime.now());
    if (f == null) return 'ORCA SOS — $time (GPS unavailable)';
    return 'ORCA SOS\n'
        'pos: ${f.latitude.toStringAsFixed(5)}, ${f.longitude.toStringAsFixed(5)}\n'
        'acc: ±${f.accuracy.toStringAsFixed(0)} m · spd: ${(f.speed * 1.943844).toStringAsFixed(1)} kn\n'
        'time: $time\n'
        'maps: https://maps.google.com/?q=${f.latitude.toStringAsFixed(5)},${f.longitude.toStringAsFixed(5)}';
  }

  Future<void> _sendSms() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    if (!Platform.isAndroid) {
      // iOS/desktop: prefilled SMS app kholo (honest fallback)
      await launchUrl(Uri.parse(
          'sms:$phone?body=${Uri.encodeComponent(_smsBody)}'));
      return;
    }
    try {
      final telephony = Telephony.instance;
      final perm = await telephony.requestPhoneAndSmsPermissions ?? false;
      if (perm != true) {
        await _smsFallback(phone); // permission nahi mili — SMS app kholo
        return;
      }
      await telephony.sendSms(to: phone, message: _smsBody);
      if (mounted) setState(() => _smsState = 'sent');
    } catch (_) {
      await _smsFallback(phone); // SIM/radio dikkat — honest fallback
    }
  }

  /// Direct send fail hua to prefilled SMS app kholo + state 'fallback'.
  /// Fisher ko clear dikhe: app ne koshish ki, ab SEND usko khud dabana hai.
  Future<void> _smsFallback(String phone) async {
    try {
      await launchUrl(Uri.parse(
          'sms:$phone?body=${Uri.encodeComponent(_smsBody)}'));
      if (mounted) setState(() => _smsState = 'fallback');
    } catch (_) {
      if (mounted) setState(() => _smsState = 'fail');
    }
  }

  List<({Harbour h, double nm, String dir})> get _nearest {
    final f = _fix;
    if (f == null) return const [];
    final list = kHarbours.map((h) {
      final km = Marine.haversineKm(f.latitude, f.longitude, h.lat, h.lon);
      final brg = Marine.bearingDeg(f.latitude, f.longitude, h.lat, h.lon);
      return (h: h, nm: Marine.kmToNm(km), dir: Marine.compass16(brg));
    }).toList()
      ..sort((a, b) => a.nm.compareTo(b.nm));
    return list.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final f = _fix;
    return ListView(padding: const EdgeInsets.all(16), children: [
      // header
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: OrcaTheme.dangerRed.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: OrcaTheme.dangerRed.withOpacity(0.4)),
        ),
        child: Column(children: [
          Text('sos_title'.tr(),
              style: t.textTheme.titleLarge
                  ?.copyWith(color: OrcaTheme.dangerRed, fontSize: 20)),
          const SizedBox(height: 4),
          Text('sos_offline'.tr(),
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(fontSize: 12.5)),
        ]),
      ),

      // GIANT position card (GPS = satellites, net ki zaroorat NAHI)
      OrcaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('sos_position'.tr(),
                    style: t.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(
                onPressed: _refresh,
                icon: Icon(Icons.refresh_rounded,
                    size: 18, color: t.colorScheme.secondary)),
          ]),
          SelectableText(_posText,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: f != null
                      ? t.colorScheme.onSurface
                      : OrcaTheme.dangerRed)),
          if (f != null)
            Text(
                '±${f.accuracy.toStringAsFixed(0)} m · GPS satellites se (network nahi chahiye)',
                style: t.textTheme.bodyMedium?.copyWith(
                    fontSize: 11, color: t.colorScheme.secondary)),
        ]),
      ),

      // Coast Guard 1554 — biggest button
      SizedBox(
        width: double.infinity,
        height: 64,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: OrcaTheme.dangerRed,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16))),
          icon: const Icon(Icons.call_rounded, color: Colors.white, size: 24),
          label: Text('sos_call'.tr(),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
          onPressed: () => launchUrl(Uri.parse('tel:1554')),
        ),
      ),
      const SizedBox(height: 12),

      // contact + direct SMS
      OrcaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('sos_send_sms'.tr(),
              style: t.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                    hintText: '👤 Naam',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11))),
                onChanged: (_) => _saveContact(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                    hintText: '98XXXXXX01',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11))),
                onChanged: (_) => _saveContact(),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _phoneCtrl.text.trim().isEmpty
                    ? null
                    : () => launchUrl(
                        Uri.parse('tel:${_phoneCtrl.text.trim()}')),
                icon: const Icon(Icons.call_rounded, size: 17),
                label: const Text('Call'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: OrcaTheme.teal),
                onPressed: _phoneCtrl.text.trim().isEmpty ? null : _sendSms,
                icon: const Icon(Icons.sms_rounded,
                    size: 17, color: Colors.white),
                label: Text(_smsState == 'sent' ? 'sms_sent'.tr() : 'SMS',
                    style: const TextStyle(color: Colors.white)),
              ),
            ),
          ]),
          if (_smsState == 'fallback')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('sos_sms_fallback'.tr(),
                  style: const TextStyle(
                      color: OrcaTheme.warnAmber,
                      fontWeight: FontWeight.w700)),
            ),
          if (_smsState == 'fail')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('sms_fail'.tr(),
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: OrcaTheme.dangerRed,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
      ),

      // nearest harbours (all offline — 71 bundled, GLOBE-checked)
      if (f != null && _nearest.isNotEmpty)
        OrcaCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('harbour_near'.tr(),
                style: t.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final x in _nearest)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Icon(Icons.anchor_rounded,
                      size: 16, color: t.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(x.h.name,
                          style: t.textTheme.bodyMedium
                              ?.copyWith(fontSize: 13.5))),
                  Text('${x.nm.toStringAsFixed(1)} NM ${x.dir}',
                      style: t.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: t.colorScheme.secondary,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),

      // no-signal card (gap #1: VHF Ch16 proper)
      OrcaCard(
        bg: OrcaTheme.dangerRed.withOpacity(0.05),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _noSig(Icons.settings_input_antenna_rounded, 'vhf_note'.tr()),
          _noSig(Icons.campaign_rounded, 'nosig_2'.tr()),
          _noSig(Icons.groups_rounded, 'nosig_3'.tr()),
        ]),
      ),
    ]);
  }

  Widget _noSig(IconData icon, String txt) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: OrcaTheme.dangerRed),
          const SizedBox(width: 8),
          Expanded(
              child: Text(txt,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );
}
