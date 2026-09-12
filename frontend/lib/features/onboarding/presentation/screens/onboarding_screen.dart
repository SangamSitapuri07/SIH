import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/widgets/orca_app_bar.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

/// First-run onboarding wizard for selecting server URL, language, and mode (§8).
class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onFinish;

  const OnboardingScreen({
    super.key,
    required this.onFinish,
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late TextEditingController _urlController;
  String _selectedLang = 'en';
  bool _demoMode = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ref.read(baseUrlProvider));
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OrcaTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo & Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: OrcaTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.waves, color: OrcaTheme.accent, size: 32),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ORCA',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        'Marine Safety & Ecology Advisor',
                        style: TextStyle(
                          fontSize: 12,
                          color: OrcaTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 30),

              const Text(
                'Welcome to ORCA Setup',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Configure your ORCA Box connection and preferred language to begin.',
                style: TextStyle(fontSize: 13, color: OrcaTheme.textSecondary, height: 1.3),
              ),
              const SizedBox(height: 24),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Language selector
                      const Text(
                        '1. SELECT LANGUAGE / भाषा चुनें / భాషను ఎంచుకోండి',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: OrcaTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _langChip('English', 'en'),
                          const SizedBox(width: 8),
                          _langChip('हिन्दी', 'hi'),
                          const SizedBox(width: 8),
                          _langChip('తెలుగు', 'te'),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 2. Server URL input
                      const Text(
                        '2. ORCA BOX SERVER IP / URL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: OrcaTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _urlController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: OrcaTheme.surface,
                          hintText: 'http://10.0.2.2:8000',
                          hintStyle: const TextStyle(color: OrcaTheme.textMuted),
                          prefixIcon: const Icon(Icons.dns, color: OrcaTheme.accent, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: OrcaTheme.cardBorder),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 3. Demo Mode Toggle
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: OrcaTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OrcaTheme.cardBorder),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Enable Judge Demo Mode',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          subtitle: const Text(
                            'Uses bundled offline fixtures without requiring a live laptop server',
                            style: TextStyle(fontSize: 11, color: OrcaTheme.textMuted),
                          ),
                          value: _demoMode,
                          activeThumbColor: VerdictColors.caution,
                          onChanged: (val) => setState(() => _demoMode = val),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Get Started Button
              ElevatedButton(
                onPressed: () async {
                  ref.read(baseUrlProvider.notifier).state = _urlController.text.trim();
                  ref.read(selectedLocaleProvider.notifier).state = _selectedLang;
                  ref.read(demoModeProvider.notifier).state = _demoMode;
                  final cache = ref.read(cacheServiceProvider);
                  await cache.put('settings.base_url', <String, dynamic>{'value': _urlController.text.trim()}, ttl: const Duration(days: 3650));
                  await cache.put('settings.locale', <String, dynamic>{'value': _selectedLang}, ttl: const Duration(days: 3650));
                  await cache.put('settings.demo_mode', <String, dynamic>{'value': _demoMode}, ttl: const Duration(days: 3650));
                  await cache.put(
                    'app.onboarding',
                    <String, dynamic>{'complete': true},
                    ttl: const Duration(days: 3650),
                  );
                  widget.onFinish();
                },
                child: const Text('Get Started with ORCA'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _langChip(String label, String code) {
    final isSelected = _selectedLang == code;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedLang = code),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? OrcaTheme.accent : OrcaTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? OrcaTheme.accent : OrcaTheme.cardBorder,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
