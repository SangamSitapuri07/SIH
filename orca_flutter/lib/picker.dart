import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

/// First-launch language picker — 11 bhash apni script mein, flags NAHI.
class LanguagePickerScreen extends StatefulWidget {
  final Settings settings;
  const LanguagePickerScreen({super.key, required this.settings});

  @override
  State<LanguagePickerScreen> createState() => _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends State<LanguagePickerScreen> {
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 28),
          const Text('🐋', style: TextStyle(fontSize: 44)),
          Text('ORCA', style: t.textTheme.titleLarge?.copyWith(fontSize: 30)),
          const SizedBox(height: 4),
          Text('tagline'.tr(),
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: t.colorScheme.secondary)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('choose_language'.tr(),
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: LangRef.langs.length,
              itemBuilder: (_, i) {
                final l = LangRef.langs[i];
                final sel = i == _sel;
                return GestureDetector(
                  onTap: () {
                    setState(() => _sel = i);
                    context.setLocale(l.locale); // live preview
                  },
                  child: Container(
                    height: 54,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color:
                          sel ? t.colorScheme.primary : t.colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: sel
                              ? t.colorScheme.primary
                              : t.dividerColor,
                          width: sel ? 2 : 1),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                  color: t.colorScheme.primary
                                      .withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4))
                            ]
                          : null,
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(l.native,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: sel
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: sel
                                    ? Colors.white
                                    : t.colorScheme.onSurface)),
                      ),
                      Text(l.eng,
                          style: TextStyle(
                              fontSize: 12,
                              color: sel
                                  ? Colors.white70
                                  : t.colorScheme.secondary)),
                      if (sel) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle,
                            color: Colors.white, size: 20),
                      ],
                    ]),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: OrcaTheme.teal,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                onPressed: widget.settings.setLangChosen,
                child: Text('cont'.tr(),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
