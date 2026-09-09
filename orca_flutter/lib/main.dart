import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'picker.dart';
import 'screens/ai_tab.dart';
import 'screens/home.dart';
import 'screens/info.dart';
import 'screens/map_screen.dart';
// (B10) Navigate tab abhi ANDROID se hata diya — pehle web pe polish + test
// hoga; flutter screen files (navigate.dart, route_analysis.dart) safe hain
// aur wapas wire ho jayengi jab flow final ho.
import 'screens/sos.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Languages — 11/11 (har JSON complete; native name apni script mein)
// ─────────────────────────────────────────────────────────────────────────────
const kLangs = <({Locale locale, String native, String eng})>[
  (locale: Locale('hi'), native: 'हिन्दी', eng: 'Hindi'),
  (locale: Locale('en'), native: 'English', eng: 'English'),
  (locale: Locale('gu'), native: 'ગુજરાતી', eng: 'Gujarati'),
  (locale: Locale('or'), native: 'ଓଡ଼ିଆ', eng: 'Odia'),
  (locale: Locale('bn'), native: 'বাংলা', eng: 'Bengali'),
  (locale: Locale('ta'), native: 'தமிழ்', eng: 'Tamil'),
  (locale: Locale('te'), native: 'తెలుగు', eng: 'Telugu'),
  (locale: Locale('ml'), native: 'മലയാളം', eng: 'Malayalam'),
  (locale: Locale('kn'), native: 'ಕನ್ನಡ', eng: 'Kannada'),
  (locale: Locale('mr'), native: 'मराठी', eng: 'Marathi'),
  (locale: Locale('kok'), native: 'कोंकणी', eng: 'Konkani'),
];

// ─────────────────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  LangRef.langs = kLangs;
  final settings = Settings();
  await settings.load();
  final app = AppState();
  await app.loadDemoOrigin(); // (B6) persisted manual start point
  runApp(EasyLocalization(
    supportedLocales: kLangs.map((l) => l.locale).toList(),
    path: 'assets/i18n',
    fallbackLocale: const Locale('hi'),
    startLocale: const Locale('hi'),
    child: OrcaApp(settings: settings, app: app),
  ));
}

class OrcaApp extends StatelessWidget {
  final Settings settings;
  final AppState app;
  const OrcaApp({super.key, required this.settings, required this.app});

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
            if (dhoop) tree = Theme(data: OrcaTheme.dhoop(), child: tree);
            return MediaQuery(
              data: MediaQuery.of(mctx)
                  .copyWith(textScaler: TextScaler.linear(settings.scale)),
              child: tree,
            );
          },
          home: settings.langChosen
              ? HomeShell(settings: settings, app: app)
              : LanguagePickerScreen(settings: settings),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home shell — StatusStrip + 5 tabs (SOS hamesha RED) + shared AppState
// ─────────────────────────────────────────────────────────────────────────────
class HomeShell extends StatefulWidget {
  final Settings settings;
  final AppState app;
  const HomeShell({super.key, required this.settings, required this.app});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    widget.app.jumpTab = (i) => setState(() => _index = i);
    _pages = [
      HomeScreen(settings: widget.settings, app: widget.app),
      MapScreen(settings: widget.settings, app: widget.app),
      // (B10) NavigateScreen hidden — testing on web first
      AiTab(settings: widget.settings, app: widget.app),
      SosScreen(settings: widget.settings, app: widget.app),
      InfoScreen(settings: widget.settings, app: widget.app),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          StatusStrip(settings: widget.settings),
          const Divider(height: 1),
          Expanded(child: IndexedStack(index: _index, children: _pages)),
        ]),
      ),
      bottomNavigationBar: _BottomBar(
          index: _index, onTap: (i) => setState(() => _index = i)),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String, bool)>[
      (Icons.home_rounded, 'tab_home', false),
      (Icons.map_rounded, 'tab_map', false),
      // (B10) tab_nav hidden for now — web par polish hame pehle karni hai
      (Icons.psychology_alt_rounded, 'tab_ai', false),
      (Icons.sos_rounded, 'tab_sos', true),
      (Icons.info_outline_rounded, 'tab_info', false),
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
                  icon: items[i].$1,
                  labelKey: items[i].$2,
                  isSos: items[i].$3,
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

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String labelKey;
  final bool isSos, selected;
  final VoidCallback onTap;
  const _TabButton(
      {required this.icon,
      required this.labelKey,
      required this.isSos,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final Color color = isSos
        ? OrcaTheme.dangerRed // SOS hamesha red (plan §10 #7)
        : (selected ? t.colorScheme.primary : t.colorScheme.secondary);
    return InkResponse(
      onTap: onTap,
      radius: 34,
      child: SizedBox(
        width: 62,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: isSos ? 28 : 24, color: color),
          const SizedBox(height: 2),
          Text(labelKey.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: color)),
        ]),
      ),
    );
  }
}
