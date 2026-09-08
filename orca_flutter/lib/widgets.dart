import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'state.dart';
import 'theme.dart';

/// Language list is defined in main.dart as kLangs (circular import avoid:
/// widgets gets them via a static set by main at startup).
class LangRef {
  static List<({Locale locale, String native, String eng})> langs = [];
}

/// ORCA card — white, rounded 18, hairline border, soft shadow.
class OrcaCard extends StatelessWidget {
  final Widget child;
  final Color? bg;
  final Color? border;
  final EdgeInsets? padding;
  const OrcaCard(
      {super.key, required this.child, this.bg, this.border, this.padding});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg ?? t.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border ?? t.dividerColor),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: child,
    );
  }
}

class ComingChip extends StatelessWidget {
  const ComingChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: OrcaTheme.mintChip, borderRadius: BorderRadius.circular(999)),
      child: Text('coming_badge'.tr(),
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F766E))),
    );
  }
}

/// StatusStrip — net status · 🌐 language (1 tap) · mode cycle · zoom A−/A+.
class StatusStrip extends StatefulWidget {
  final Settings settings;
  const StatusStrip({super.key, required this.settings});

  @override
  State<StatusStrip> createState() => _StatusStripState();
}

class _StatusStripState extends State<StatusStrip> {
  StreamSubscription? _sub;
  bool _online = true;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_apply);
    _sub = Connectivity().onConnectivityChanged.listen(_apply);
  }

  void _apply(dynamic r) {
    final list = r is List<ConnectivityResult>
        ? r
        : <ConnectivityResult>[r as ConnectivityResult];
    final on = list.any((c) => c != ConnectivityResult.none);
    if (mounted && on != _online) setState(() => _online = on);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = widget.settings;
    final modeIcon = switch (s.mode) {
      1 => Icons.dark_mode_rounded,
      2 => Icons.wb_sunny_rounded,
      _ => Icons.light_mode_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Icon(_online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            size: 16, color: _online ? OrcaTheme.okGreen : OrcaTheme.dangerRed),
        const SizedBox(width: 5),
        Text(_online ? 'online'.tr() : 'offline'.tr(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _online ? OrcaTheme.okGreen : OrcaTheme.dangerRed)),
        const Spacer(),
        _StripBtn(
          onTap: () => _showLangSheet(context),
          child: Icon(Icons.language_rounded,
              size: 18, color: t.colorScheme.secondary),
        ),
        _StripBtn(
          onTap: s.cycleMode,
          child: Icon(modeIcon, size: 18, color: t.colorScheme.secondary),
        ),
        _StripBtn(
          onTap: s.scale > 0.86 ? () => s.zoom(false) : null,
          child: Text('A−',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: t.colorScheme.secondary)),
        ),
        _StripBtn(
          onTap: s.scale < 1.74 ? () => s.zoom(true) : null,
          child: Text('A+',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: t.colorScheme.secondary)),
        ),
      ]),
    );
  }

  static void _showLangSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (bctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: LangRef.langs.length,
          itemBuilder: (_, i) {
            final l = LangRef.langs[i];
            final sel = context.locale == l.locale;
            return ListTile(
              title: Text(l.native,
                  style: TextStyle(
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w500)),
              trailing: sel
                  ? Icon(Icons.check_circle,
                      color: Theme.of(bctx).colorScheme.primary)
                  : Text(l.eng, style: const TextStyle(fontSize: 12)),
              onTap: () {
                context.setLocale(l.locale);
                Navigator.pop(bctx);
              },
            );
          },
        ),
      ),
    );
  }
}

class _StripBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _StripBtn({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
        onTap: onTap,
        radius: 24,
        child: Padding(padding: const EdgeInsets.all(7), child: child));
  }
}

/// Error block with honest reason + retry — used by every data screen.
class FetchError extends StatelessWidget {
  final String detail;
  final VoidCallback onRetry;
  const FetchError({super.key, required this.detail, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return OrcaCard(
      border: OrcaTheme.dangerRed.withOpacity(0.45),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.error_outline_rounded,
              size: 17, color: OrcaTheme.dangerRed),
          const SizedBox(width: 6),
          Text('fetch_failed'.tr(),
              style: t.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800, color: OrcaTheme.dangerRed)),
        ]),
        const SizedBox(height: 6),
        Text(detail,
            style: t.textTheme.bodyMedium
                ?.copyWith(fontSize: 11.5, color: t.colorScheme.secondary)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text('retry_lbl'.tr())),
      ]),
    );
  }
}
