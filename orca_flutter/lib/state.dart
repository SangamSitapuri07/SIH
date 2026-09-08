import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Nav target shared between Map → Navigate tabs.
class NavTarget {
  final String name;
  final double lat;
  final double lon;
  const NavTarget(this.name, this.lat, this.lon);
}

/// App-wide shared state (single instance from main).
class AppState extends ChangeNotifier {
  NavTarget? navTarget;
  Position? lastFix; // last GPS fix — Home/SOS/Nav share karte hain
  void Function(int tabIndex)? jumpTab;

  void setTarget(NavTarget t) {
    navTarget = t;
    notifyListeners();
  }

  void clearTarget() {
    navTarget = null;
    notifyListeners();
  }

  void setFix(Position p) {
    lastFix = p;
    // no notify — screens read on their own cadence
  }
}

/// Settings — persisted (display mode, zoom, backend base, lang chosen).
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
    (await SharedPreferences.getInstance()).setInt(_kMode, m);
  }

  Future<void> zoom(bool up) async {
    final next = (scale + (up ? 0.15 : -0.15)).clamp(0.85, 1.75);
    scale = double.parse(next.toStringAsFixed(2));
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_kScale, scale);
  }

  Future<void> setBase(String b) async {
    base = b.trim();
    notifyListeners();
    (await SharedPreferences.getInstance()).setString(_kBase, base);
  }

  Future<void> setLangChosen() async {
    langChosen = true;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_kChosen, true);
  }
}
