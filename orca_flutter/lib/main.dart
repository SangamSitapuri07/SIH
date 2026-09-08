import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Languages — 11/11 (har JSON complete; native name apni script mein)
// ─────────────────────────────────────────────────────────────────────────────
class Lang {
  final Locale locale;
  final String native;
  final String eng;
  const Lang(this.locale, this.native, this.eng);
}

const kLangs = <Lang>[
  Lang(Locale('hi'), 'हिन्दी', 'Hindi'),
  Lang(Locale('en'), 'English', 'English'),
  Lang(Locale('gu'), 'ગુજરાતી', 'Gujarati'),
  Lang(Locale('or'), 'ଓଡ଼ିଆ', 'Odia'),
  Lang(Locale('bn'), 'বাংলা', 'Bengali'),
  Lang(Locale('ta'), 'தமிழ்', 'Tamil'),
  Lang(Locale('te'), 'తెలుగు', 'Telugu'),
  Lang(Locale('ml'), 'മലയാളം', 'Malayalam'),
  Lang(Locale('kn'), 'ಕನ್ನಡ', 'Kannada'),
  Lang(Locale('mr'), 'मराठी', 'Marathi'),
  Lang(Locale('kok'), 'कोंकणी', 'Konkani'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Settings — persisted (display mode, zoom scale, backend base, lang chosen)
// ─────────────────────────────────────────────────────────────────────────────
class Settings extends ChangeNotifier {
  static const _kMode = 'orca_mode'; // 0=light(default) 1=dark 2=dhoop
  static const _kScale = 'orca_scale'; // 0.85 .. 1.75
  static const _kBase = 'orca_api_base';
  static const _kChosen = 'orca_lang_chosen';

  int mode = 0;
  double scale = 1.0;
  String base = OrcaApi.defaultBase;
  bool langChosen = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode = p.getInt(_kMode) ?? 0;
    scale = p.getDouble(_kScale) ?? 1.0;
    base = p.getString(_kBase) ?? OrcaApi.defaultBase;
    langChosen = p.getBool(_kChosen) ?? false;
    notifyListeners();
  }

  Future<void> cycleMode() => setMode((mode + 1) % 3);

  Future<void> setMode(int m) async {
    mode = m;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMode, m);
  }

  Future<void> zoom(bool up) async {
    final next = (scale + (up ? 0.15 : -0.15)).clamp(0.85, 1.75);
    scale = double.parse(next.toStringAsFixed(2));
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kScale, scale);
  }

  Future<void> setBase(String b) async {
    base = b.trim();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBase, base);
  }

  Future<void> setLangChosen() async {
    langChosen = true;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kChosen, true);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  final settings = Settings();
  await settings.load();
  runApp(EasyLocalization(
    supportedLocales: kLangs.map((l) => l.locale).toList(),
    path: 'assets/i18n',
    fallbackLocale: const Locale('hi'),
    startLocale: const Locale('hi'),
    child: OrcaApp(settings: settings),
  ));
}

class OrcaApp extends StatelessWidget {
  final Settings settings;
  const OrcaApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (ctx, _) {
        final dhoop = settings.mode == 2;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'ORCA',
          theme: OrcaTheme.light(),
          darkTheme: OrcaTheme.dark(),
          themeMode: settings.mode == 1 ? ThemeMode.dark : ThemeMode.light,
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          // dhoop = 3rd theme via Theme override; zoom = app-wide textScaler
          builder: (mctx, child) {
            Widget tree = child!;
            if (dhoop) {
              tree = Theme(data: OrcaTheme.dhoop(), child: tree);
            }
            return MediaQuery(
              data: MediaQuery.of(mctx)
                  .copyWith(textScaler: TextScaler.linear(settings.scale)),
              child: tree,
            );
          },
          home: settings.langChosen
              ? HomeShell(settings: settings)
              : LanguagePickerScreen(settings: settings),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// First-launch language picker (flags NAHI — apni script mein naam)
// ─────────────────────────────────────────────────────────────────────────────
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
        child: Column(
          children: [
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
                itemCount: kLangs.length,
                itemBuilder: (_, i) {
                  final l = kLangs[i];
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
                        color: sel
                            ? t.colorScheme.primary
                            : t.colorScheme.surface,
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
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(l.native,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight:
                                        sel ? FontWeight.w800 : FontWeight.w500,
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
                        ],
                      ),
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
                  onPressed: () async {
                    await widget.settings.setLangChosen();
                  },
                  child: Text('cont'.tr(),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home shell — StatusStrip + 5 tabs (SOS tab hamesha RED)
// ─────────────────────────────────────────────────────────────────────────────
class HomeShell extends StatefulWidget {
  final Settings settings;
  const HomeShell({super.key, required this.settings});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final pages = <Widget>[
      HomeScreen(settings: s),
      MapScreen(settings: s),
      NavigateScreen(settings: s),
      SosScreen(settings: s),
      InfoScreen(settings: s),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            StatusStrip(settings: s),
            const Divider(height: 1),
            Expanded(child: IndexedStack(index: _index, children: pages)),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = <_TabDef>[
      _TabDef(Icons.home_rounded, 'tab_home'),
      _TabDef(Icons.map_rounded, 'tab_map'),
      _TabDef(Icons.explore_rounded, 'tab_nav'),
      _TabDef(Icons.sos_rounded, 'tab_sos', isSos: true),
      _TabDef(Icons.info_outline_rounded, 'tab_info'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++)
                _TabButton(
                  def: items[i],
                  selected: index == i,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabDef {
  final IconData icon;
  final String labelKey;
  final bool isSos;
  const _TabDef(this.icon, this.labelKey, {this.isSos = false});
}

class _TabButton extends StatelessWidget {
  final _TabDef def;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton(
      {required this.def, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final Color color = def.isSos
        ? OrcaTheme.dangerRed // SOS hamesha red (plan §10 #7)
        : (selected ? t.colorScheme.primary : t.colorScheme.secondary);
    return InkResponse(
      onTap: onTap,
      radius: 34,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(def.icon, size: def.isSos ? 28 : 24, color: color),
            const SizedBox(height: 2),
            Text(def.labelKey.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StatusStrip — net status · 1-tap language · 1-tap mode cycle · zoom A-/A+
// ─────────────────────────────────────────────────────────────────────────────
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
    final list = r is List<ConnectivityResult> ? r : <ConnectivityResult>[r as ConnectivityResult];
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
    IconData modeIcon = switch (s.mode) {
      1 => Icons.dark_mode_rounded,
      2 => Icons.wb_sunny_rounded,
      _ => Icons.light_mode_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            _online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            size: 16,
            color: _online ? OrcaTheme.okGreen : OrcaTheme.dangerRed,
          ),
          const SizedBox(width: 5),
          Text(
            _online ? 'online'.tr() : 'offline'.tr(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _online ? OrcaTheme.okGreen : OrcaTheme.dangerRed),
          ),
          const Spacer(),
          // 🌐 language — 1 tap
          _StripBtn(
            child: Icon(Icons.language_rounded,
                size: 18, color: t.colorScheme.secondary),
            onTap: () => _showLangSheet(context),
          ),
          // ☀/🌙/🔆 mode — 1 tap cycle (light→dark→dhoop)
          _StripBtn(
            child: Icon(modeIcon, size: 18, color: t.colorScheme.secondary),
            onTap: s.cycleMode,
          ),
          // A- zoom out
          _StripBtn(
            child: Text('A−',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: t.colorScheme.secondary)),
            onTap: s.scale > 0.86 ? () => s.zoom(false) : null,
          ),
          // A+ zoom in
          _StripBtn(
            child: Text('A+',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: t.colorScheme.secondary)),
            onTap: s.scale < 1.74 ? () => s.zoom(true) : null,
          ),
        ],
      ),
    );
  }

  static void _showLangSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (bctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: kLangs.length,
          itemBuilder: (_, i) {
            final l = kLangs[i];
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
      child: Padding(padding: const EdgeInsets.all(7), child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared cards
// ─────────────────────────────────────────────────────────────────────────────
class OrcaCard extends StatelessWidget {
  final Widget child;
  final Color? bg;
  final Color? border;
  const OrcaCard({super.key, required this.child, this.bg, this.border});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
        color: OrcaTheme.mintChip,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('coming_badge'.tr(),
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F766E))),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screens (D1 = honest stubs; real data D2-D6 ke din aayega)
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  final Settings settings;
  const HomeScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('greeting_morning'.tr(),
            style: t.textTheme.bodyMedium
                ?.copyWith(color: t.colorScheme.secondary, fontSize: 13)),
        Row(
          children: [
            Text('ORCA',
                style: t.textTheme.titleLarge
                    ?.copyWith(fontSize: 26, letterSpacing: 0.5)),
            const Spacer(),
            const _Avatar(),
          ],
        ),
        const SizedBox(height: 14),
        // 📍 मेरी जगह chip (plan §10 #4) — GPS D4 pe judega
        Row(
          children: [
            Icon(Icons.my_location_rounded,
                size: 14, color: t.colorScheme.primary),
            const SizedBox(width: 6),
            Text('my_location'.tr(),
                style: t.textTheme.bodyMedium?.copyWith(fontSize: 12.5)),
            const SizedBox(width: 6),
            Text('loc_unknown'.tr(),
                style: t.textTheme.bodyMedium?.copyWith(
                    fontSize: 12, color: t.colorScheme.secondary)),
          ],
        ),
        const SizedBox(height: 14),
        OrcaCard(
          border: OrcaTheme.teal.withOpacity(0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('home_stub'.tr(), style: t.textTheme.bodyMedium),
              const SizedBox(height: 10),
              const ComingChip(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return const CircleAvatar(
      radius: 17,
      backgroundColor: OrcaTheme.mintChip,
      child: Text('RS',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F766E))),
    );
  }
}

class MapScreen extends StatelessWidget {
  final Settings settings;
  const MapScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_rounded,
                size: 46, color: t.colorScheme.primary.withOpacity(0.7)),
            const SizedBox(height: 12),
            Text('map_stub'.tr(),
                textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
            const SizedBox(height: 10),
            const ComingChip(),
          ],
        ),
      ),
    );
  }
}

class NavigateScreen extends StatelessWidget {
  final Settings settings;
  const NavigateScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_rounded,
                size: 46, color: t.colorScheme.primary.withOpacity(0.7)),
            const SizedBox(height: 12),
            Text('nav_stub'.tr(),
                textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
            const SizedBox(height: 10),
            const ComingChip(),
          ],
        ),
      ),
    );
  }
}

class SosScreen extends StatelessWidget {
  final Settings settings;
  const SosScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: OrcaTheme.dangerRed.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OrcaTheme.dangerRed.withOpacity(0.4)),
          ),
          child: Column(
            children: [
              Text('sos_title'.tr(),
                  style: t.textTheme.titleLarge
                      ?.copyWith(color: OrcaTheme.dangerRed, fontSize: 20)),
              const SizedBox(height: 4),
              Text('sos_offline'.tr(),
                  textAlign: TextAlign.center,
                  style:
                      t.textTheme.bodyMedium?.copyWith(fontSize: 12.5)),
            ],
          ),
        ),
        OrcaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('sos_where'.tr(),
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('loc_unknown'.tr(),
                  style: t.textTheme.bodyMedium
                      ?.copyWith(color: t.colorScheme.secondary)),
              const SizedBox(height: 8),
              const ComingChip(),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: OrcaTheme.dangerRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16))),
            icon: const Icon(Icons.call_rounded, color: Colors.white),
            label: Text('sos_call'.tr(),
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            onPressed: () => launchUrl(Uri.parse('tel:1554')),
          ),
        ),
      ],
    );
  }
}

class InfoScreen extends StatefulWidget {
  final Settings settings;
  const InfoScreen({super.key, required this.settings});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  late final TextEditingController _baseCtrl;
  String _conn = ''; // '', 'checking', 'ok', 'fail'
  String _connDetail = '';

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
        _connDetail = '⎇ ${h['commit'] ?? h['version'] ?? 'ok'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _conn = 'fail';
        _connDetail = '$e'; // honest reason dikhta hai
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = widget.settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('info_title'.tr(), style: t.textTheme.titleLarge),
        const SizedBox(height: 14),

        // ── भाषा ──
        OrcaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('language_lbl'.tr(),
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final l in kLangs)
                    _LangChip(
                        lang: l, selected: context.locale == l.locale),
                ],
              ),
              const SizedBox(height: 8),
              Text('feedback_note'.tr(),
                  style: t.textTheme.bodyMedium?.copyWith(
                      fontSize: 11.5, color: t.colorScheme.secondary)),
            ],
          ),
        ),

        // ── Display mode ──
        OrcaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('display_mode'.tr(),
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _ModeBtn(
                      label: 'mode_light'.tr(),
                      icon: Icons.light_mode_rounded,
                      selected: s.mode == 0,
                      onTap: () => s.setMode(0)),
                  const SizedBox(width: 8),
                  _ModeBtn(
                      label: 'mode_dark'.tr(),
                      icon: Icons.dark_mode_rounded,
                      selected: s.mode == 1,
                      onTap: () => s.setMode(1)),
                  const SizedBox(width: 8),
                  _ModeBtn(
                      label: 'mode_dhoop'.tr(),
                      icon: Icons.wb_sunny_rounded,
                      selected: s.mode == 2,
                      onTap: () => s.setMode(2)),
                ],
              ),
            ],
          ),
        ),

        // ── Text size (zoom) ──
        OrcaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('text_size'.tr(),
                      style: t.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${(s.scale * 100).round()}%',
                      style: t.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: t.colorScheme.secondary,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ZoomBtn(icon: Icons.remove_rounded, onTap: () => s.zoom(false)),
                  Expanded(
                    child: Center(
                      child: Text('preview'.tr(),
                          style: t.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  _ZoomBtn(icon: Icons.add_rounded, onTap: () => s.zoom(true)),
                ],
              ),
            ],
          ),
        ),

        // ── Offline translator (D6 wiring; abhi honest note) ──
        OrcaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('translator_title'.tr(),
                        style: t.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  const ComingChip(),
                ],
              ),
              const SizedBox(height: 6),
              Text('translator_desc'.tr(),
                  style: t.textTheme.bodyMedium?.copyWith(
                      fontSize: 12.5, color: t.colorScheme.secondary)),
            ],
          ),
        ),

        // ── Backend connection ──
        OrcaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  fillColor: t.colorScheme.surfaceContainerHighest
                      .withOpacity(0.35),
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
              Row(
                children: [
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
                    Icon(Icons.check_circle,
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
                ],
              ),
            ],
          ),
        ),

        // ── ईमानदारी Charter (plan §10 #5 — judges USP) ──
        OrcaCard(
          border: OrcaTheme.warnAmber.withOpacity(0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('honesty_title'.tr(),
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              _HonestRow(icon: Icons.verified_user_rounded, keyText: 'honest_1'),
              _HonestRow(icon: Icons.schedule_rounded, keyText: 'honest_2'),
              _HonestRow(icon: Icons.error_outline_rounded, keyText: 'honest_3'),
              _HonestRow(icon: Icons.route_rounded, keyText: 'honest_4'),
            ],
          ),
        ),

        Center(
          child: Text('version_line'.tr(),
              style: t.textTheme.bodyMedium?.copyWith(
                  fontSize: 11, color: t.colorScheme.secondary)),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _HonestRow extends StatelessWidget {
  final IconData icon;
  final String keyText;
  const _HonestRow({required this.icon, required this.keyText});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: t.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(keyText.tr(),
                  style:
                      t.textTheme.bodyMedium?.copyWith(fontSize: 13.5))),
        ],
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final Lang lang;
  final bool selected;
  const _LangChip({required this.lang, required this.selected});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GestureDetector(
      onTap: () => context.setLocale(lang.locale),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? t.colorScheme.primary : t.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? t.colorScheme.primary : t.dividerColor,
              width: selected ? 2 : 1),
        ),
        child: Text(lang.native,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? Colors.white : t.colorScheme.onSurface)),
      ),
    );
  }
}

class _ModeBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ModeBtn(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: selected ? t.colorScheme.primary : t.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? t.colorScheme.primary : t.dividerColor,
                width: selected ? 2 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : t.colorScheme.secondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500,
                        color: selected
                            ? Colors.white
                            : t.colorScheme.onSurface)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.dividerColor),
        ),
        child: Icon(icon, size: 20, color: t.colorScheme.secondary),
      ),
    );
  }
}
