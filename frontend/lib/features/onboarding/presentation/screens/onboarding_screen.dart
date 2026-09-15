import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/localization/language_options.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/theme/orca_theme.dart';
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
                          color: OrcaTheme.textPrimary,
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
                  color: OrcaTheme.textPrimary,
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final OrcaLanguageOption option in orcaLanguages)
                            _langChip(option.nativeName, option.code),
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
                        style: const TextStyle(color: OrcaTheme.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: OrcaTheme.surface,
                          hintText: '192.168.1.15 or http://192.168.1.15:8000',
                          hintStyle: const TextStyle(color: OrcaTheme.textMuted),
                          prefixIcon: const Icon(Icons.dns, color: OrcaTheme.accent, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: OrcaTheme.cardBorder),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                    ],
                  ),
                ),
              ),

              // Get Started Button
              ElevatedButton(
                onPressed: () async {
                  final baseUrl = normalizeOrcaBoxUrl(_urlController.text);
                  if (baseUrl == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter a valid IP address or http(s) URL, for example 192.168.1.15.'),
                      ),
                    );
                    return;
                  }
                  ref.read(baseUrlProvider.notifier).state = baseUrl;
                  ref.read(selectedLocaleProvider.notifier).state = _selectedLang;
                  final cache = ref.read(cacheServiceProvider);
                  await cache.put('settings.base_url', <String, dynamic>{'value': baseUrl}, ttl: const Duration(days: 3650));
                  await cache.put('settings.locale', <String, dynamic>{'value': _selectedLang}, ttl: const Duration(days: 3650));
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
    return InkWell(
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
                color: isSelected ? Colors.white : OrcaTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
  }
}
