import 'package:flutter/material.dart';

/// Languages supported by ORCA's interface.
///
/// The list covers the major languages spoken across India's coastal states.
/// Keeping it in one place prevents the onboarding, profile, header and info
/// selectors from drifting apart.
@immutable
class OrcaLanguageOption {
  final String code;
  final String nativeName;
  final String englishName;

  const OrcaLanguageOption(this.code, this.nativeName, this.englishName);

  String get label => nativeName == englishName ? nativeName : '$nativeName ($englishName)';
}

const List<OrcaLanguageOption> orcaLanguages = <OrcaLanguageOption>[
  OrcaLanguageOption('en', 'English', 'English'),
  OrcaLanguageOption('hi', 'हिन्दी', 'Hindi'),
  OrcaLanguageOption('gu', 'ગુજરાતી', 'Gujarati'),
  OrcaLanguageOption('mr', 'मराठी', 'Marathi'),
  OrcaLanguageOption('kn', 'ಕನ್ನಡ', 'Kannada'),
  OrcaLanguageOption('ml', 'മലയാളം', 'Malayalam'),
  OrcaLanguageOption('ta', 'தமிழ்', 'Tamil'),
  OrcaLanguageOption('te', 'తెలుగు', 'Telugu'),
  OrcaLanguageOption('or', 'ଓଡ଼ିଆ', 'Odia'),
  OrcaLanguageOption('bn', 'বাংলা', 'Bengali'),
];

const List<Locale> orcaSupportedLocales = <Locale>[
  Locale('en'),
  Locale('hi'),
  Locale('gu'),
  Locale('mr'),
  Locale('kn'),
  Locale('ml'),
  Locale('ta'),
  Locale('te'),
  Locale('or'),
  Locale('bn'),
];

bool isSupportedOrcaLanguage(String code) =>
    orcaLanguages.any((OrcaLanguageOption language) => language.code == code);
