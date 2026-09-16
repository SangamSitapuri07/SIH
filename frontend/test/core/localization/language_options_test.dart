import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/core/localization/language_options.dart';
import 'package:orca_app/l10n/app_localizations.dart';

void main() {
  test('all major Indian coastal-region languages are selectable', () {
    expect(
      orcaLanguages.map((language) => language.code).toSet(),
      containsAll(<String>{
        'en', 'hi', 'gu', 'mr', 'kn', 'ml', 'ta', 'te', 'or', 'bn',
      }),
    );
    expect(orcaSupportedLocales, hasLength(orcaLanguages.length));
  });

  test('additional coastal locales load translated primary navigation', () {
    expect(lookupAppLocalizations(const Locale('gu')).tabMap, 'નકશો');
    expect(lookupAppLocalizations(const Locale('mr')).tabAlerts, 'इशारे');
    expect(lookupAppLocalizations(const Locale('ta')).tabNavigate, 'வழி');
    expect(lookupAppLocalizations(const Locale('bn')).tabHome, 'প্রধান');
  });
}
