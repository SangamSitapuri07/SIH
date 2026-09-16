import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/supabase_auth_service.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/localization/language_options.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/widgets/orca_navigation.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/auth_provider.dart';

/// On-device skipper preferences.
///
/// Nothing here claims a cloud identity, a vessel or a harbour the skipper has
/// not entered themselves; every field is stored locally and can be left empty.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserProfile profile = ref.watch(userProfileProvider);
    final String name = profile.displayName.trim().isEmpty ? 'Guest skipper' : profile.displayName.trim();
    final String vesselDescription = profile.vesselType.trim().isEmpty
        ? 'Not set'
        : (profile.vesselRegistration?.trim().isNotEmpty ?? false)
            ? '${profile.vesselType} · ${profile.vesselRegistration}'
            : profile.vesselType;

    return OrcaWorkspaceScaffold(
      title: 'Profile',
      subtitle: 'Preferences stored on this device',
      locationLabel: profile.homeHarbour.trim().isEmpty ? 'Home harbour not set' : profile.homeHarbour.trim(),
      coordinateLabel: _languageLabel(profile.preferredLanguage),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: <Widget>[
          OrcaCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const OrcaBrandMark(size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(name, style: OrcaType.cardTitle),
                      const SizedBox(height: 4),
                      Text(
                        'ORCA stores these preferences on this device only. They are not an account and they are not shared with any provider.',
                        style: OrcaType.body.copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      OrcaPillButton(
                        label: 'Edit display name',
                        icon: Icons.edit_outlined,
                        onPressed: () => _editText(
                          context,
                          'Display name',
                          profile.displayName,
                          ref.read(userProfileProvider.notifier).updateDisplayName,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const OrcaSectionHeader(
            title: 'Personal & vessel settings',
            subtitle: 'Used for greetings, location labels and advisory wording',
          ),
          const SizedBox(height: 10),
          _ProfileTile(
            icon: Icons.language_outlined,
            title: 'Preferred language',
            subtitle: _languageLabel(profile.preferredLanguage),
            onTap: () => _showLanguagePicker(context, ref, profile.preferredLanguage),
          ),
          _ProfileTile(
            icon: Icons.anchor_outlined,
            title: 'Home harbour',
            subtitle: _valueOrNotSet(profile.homeHarbour),
            onTap: () => _editText(
              context,
              'Home harbour',
              profile.homeHarbour,
              ref.read(userProfileProvider.notifier).updateHomeHarbour,
            ),
          ),
          _ProfileTile(
            icon: Icons.directions_boat_outlined,
            title: 'Vessel type & registration',
            subtitle: vesselDescription,
            onTap: () => _editVessel(context, ref, profile.vesselType, profile.vesselRegistration),
          ),
          _ProfileTile(
            icon: Icons.place_outlined,
            title: 'Primary fishing area',
            subtitle: _valueOrNotSet(profile.preferredFishingArea),
            onTap: () => _editText(
              context,
              'Primary fishing area',
              profile.preferredFishingArea,
              ref.read(userProfileProvider.notifier).updateFishingArea,
            ),
          ),
          const SizedBox(height: 20),
          const OrcaSectionHeader(
            title: 'Notifications',
            subtitle: 'Device preferences; alerts still arrive from the official feeds only',
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: profile.notificationPreferences['wave_alerts'] ?? false,
            onChanged: (bool value) => ref.read(userProfileProvider.notifier).toggleNotification('wave_alerts', value),
            title: const Text('High wave & swell alerts', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('Notify me when a returned alert matches this category', style: TextStyle(fontSize: 11.5)),
            tileColor: OrcaTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: OrcaTheme.cardBorder),
            ),
            activeThumbColor: OrcaTheme.accent,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: profile.notificationPreferences['cyclone_alerts'] ?? false,
            onChanged: (bool value) => ref.read(userProfileProvider.notifier).toggleNotification('cyclone_alerts', value),
            title: const Text('Cyclone & storm alerts', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('Includes GDACS and JTWC entries when the feeds answer', style: TextStyle(fontSize: 11.5)),
            tileColor: OrcaTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: OrcaTheme.cardBorder),
            ),
            activeThumbColor: OrcaTheme.accent,
          ),
          const SizedBox(height: 20),
          const OrcaSectionHeader(
            title: 'Saved places & records',
            subtitle: 'Everything ORCA keeps about your own spots',
          ),
          const SizedBox(height: 10),
          _ProfileTile(
            icon: Icons.bookmark_border_rounded,
            title: 'Saved locations',
            subtitle: 'Harbours and fishing areas you stored',
            onTap: () => context.go('/locations'),
          ),
          _ProfileTile(
            icon: Icons.history_rounded,
            title: 'Advisory history',
            subtitle: 'Advisories the ORCA Box returned for your coordinates',
            onTap: () => context.go('/history'),
          ),
          _ProfileTile(
            icon: Icons.sailing_outlined,
            title: 'Catch reports',
            subtitle: 'Records you logged, queued offline when there is no signal',
            onTap: () => context.go('/catch-report'),
          ),
          const SizedBox(height: 18),
          const OrcaProvenance(
            source: 'Local device storage (Hive)',
            timeLabel: 'Clearing the cache on the data sources screen removes stored ORCA payloads; preferences stay on this device',
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  static String _valueOrNotSet(String value) => value.trim().isEmpty ? 'Not set' : value;

  static String _languageLabel(String value) => switch (value) {
        'hi' => 'हिंदी (Hindi)',
        'te' => 'తెలుగు (Telugu)',
        _ => 'English',
      };

  void _editText(
    BuildContext context,
    String title,
    String current,
    Future<void> Function(String) save,
  ) {
    final TextEditingController controller = TextEditingController(text: current);
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: title),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              save(controller.text.trim());
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editVessel(BuildContext context, WidgetRef ref, String vessel, String? registration) {
    final TextEditingController vesselController = TextEditingController(text: vessel);
    final TextEditingController registrationController = TextEditingController(text: registration ?? '');
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Vessel details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: vesselController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Vessel type'),
            ),
            TextField(
              controller: registrationController,
              decoration: const InputDecoration(labelText: 'Registration (optional)'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final String reg = registrationController.text.trim();
              ref
                  .read(userProfileProvider.notifier)
                  .updateVessel(vesselController.text.trim(), reg.isEmpty ? null : reg);
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, String currentLang) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: OrcaTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OrcaEyebrow('INTERFACE LANGUAGE', color: OrcaTheme.textMuted),
              ),
            ),
            for (final OrcaLanguageOption option in orcaLanguages)
              ListTile(
                title: Text(option.label),
                trailing: currentLang == option.code ? const Icon(Icons.check, color: OrcaTheme.accentDark) : null,
                onTap: () async {
                  await ref.read(userProfileProvider.notifier).updateLanguage(option.code);
                  ref.read(selectedLocaleProvider.notifier).state = option.code;
                  await ref
                      .read(cacheServiceProvider)
                      .put('settings.locale', <String, dynamic>{'value': option.code}, ttl: const Duration(days: 3650));
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OrcaCard(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(13),
        onTap: onTap,
        child: Row(
          children: <Widget>[
            OrcaIconBadge(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: OrcaType.metricLabel.copyWith(fontSize: 13, color: OrcaTheme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: OrcaType.caption.copyWith(fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 19, color: OrcaTheme.textMuted),
          ],
        ),
      );
}
