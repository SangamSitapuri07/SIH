import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/theme/orca_theme.dart';

/// Modal dialog for user-configured base URL (§2, §8).
class ServerConfigDialog extends ConsumerStatefulWidget {
  const ServerConfigDialog({super.key});

  @override
  ConsumerState<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends ConsumerState<ServerConfigDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final currentUrl = ref.read(baseUrlProvider);
    _controller = TextEditingController(text: currentUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OrcaTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: OrcaTheme.cardBorder),
      ),
      title: const Row(
        children: [
          Icon(Icons.dns, color: OrcaTheme.accent, size: 22),
          SizedBox(width: 8),
          Text(
            'ORCA Box Server URL',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the IP address of your running ORCA Box mini-PC/laptop on the same WiFi or LAN. Port 8000 is added automatically.',
            style: TextStyle(fontSize: 12, color: OrcaTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: OrcaTheme.surfaceElevated,
              hintText: '127.0.0.1 or http://192.168.1.110:8000',
              hintStyle: const TextStyle(color: OrcaTheme.textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: OrcaTheme.cardBorder),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chrome: http://127.0.0.1:8000 • Emulator: http://10.0.2.2:8000 • LAN: http://192.168.1.110:8000',
            style: TextStyle(fontSize: 11, color: OrcaTheme.textMuted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: OrcaTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () async {
            final text = _controller.text.trim();
            final normalizedUrl = normalizeOrcaBoxUrl(text);
            if (normalizedUrl == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Enter a valid IP address or http(s) URL, for example 192.168.1.15.'),
                ),
              );
              return;
            }
            ref.read(baseUrlProvider.notifier).state = normalizedUrl;
            await ref.read(cacheServiceProvider).put(
              'settings.base_url',
              <String, dynamic>{'value': normalizedUrl},
              ttl: const Duration(days: 3650),
            );
            if (!context.mounted) return;
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: OrcaTheme.accent,
            foregroundColor: Colors.black,
          ),
          child: const Text('Save URL'),
        ),
      ],
    );
  }
}
