import 'app_localizations_en.dart';

/// Translations for the additional major coastal-region languages.
///
/// Untranslated technical copy deliberately falls back to English through
/// [AppLocalizationsEn], while navigation, safety states and primary actions
/// are translated here. This gives every advertised locale a complete,
/// non-crashing localization object and lets coverage grow incrementally.
class AppLocalizationsCoastal extends AppLocalizationsEn {
  final String language;

  AppLocalizationsCoastal(this.language) : super(language);

  static const Map<String, Map<String, String>> _values = {
    'gu': {
      'appTagline': 'સહયોગી એજન્ટો સાથે સમુદ્રી પરિસ્થિતિ અને સુરક્ષા સલાહ',
      'tabHome': 'મુખ્ય', 'tabMap': 'નકશો', 'tabAi': 'AI એજન્ટો', 'tabAlerts': 'ચેતવણીઓ', 'tabNavigate': 'માર્ગ', 'tabInfo': 'માહિતી',
      'verdictGo': 'જવું સુરક્ષિત', 'verdictCaution': 'સાવચેતી', 'verdictNoGo': 'ખતરો — ન જશો', 'verdictUnknown': 'અજ્ઞાત',
      'canIGoTitle': 'શું હું આજે દરિયામાં જઈ શકું?', 'safeWindowLabel': 'સુરક્ષિત સમય', 'variablesTitle': 'વર્તમાન પરિસ્થિતિ',
      'alertsTitle': 'સક્રિય સમુદ્રી ચેતવણીઓ', 'navigateTitle': 'માર્ગ સુરક્ષા અને જમીન તપાસ', 'infoTitle': 'સિસ્ટમ અને ડેટા સ્થિતિ',
      'save': 'સાચવો', 'cancel': 'રદ કરો', 'retry': 'ફરી પ્રયાસ કરો', 'languageLabel': 'ભાષા',
    },
    'mr': {
      'appTagline': 'सहयोगी एजंटांसह सागरी परिस्थिती आणि सुरक्षा सल्ला',
      'tabHome': 'मुख्य', 'tabMap': 'नकाशा', 'tabAi': 'AI एजंट', 'tabAlerts': 'इशारे', 'tabNavigate': 'मार्ग', 'tabInfo': 'माहिती',
      'verdictGo': 'जाणे सुरक्षित', 'verdictCaution': 'सावधान', 'verdictNoGo': 'धोका — जाऊ नका', 'verdictUnknown': 'अज्ञात',
      'canIGoTitle': 'आज समुद्रात जाता येईल का?', 'safeWindowLabel': 'सुरक्षित वेळ', 'variablesTitle': 'सध्याची स्थिती',
      'alertsTitle': 'सक्रिय सागरी इशारे', 'navigateTitle': 'मार्ग सुरक्षा आणि जमीन तपासणी', 'infoTitle': 'सिस्टम आणि डेटा स्थिती',
      'save': 'जतन करा', 'cancel': 'रद्द करा', 'retry': 'पुन्हा प्रयत्न', 'languageLabel': 'भाषा',
    },
    'kn': {
      'appTagline': 'ಸಹಯೋಗಿ ಏಜೆಂಟ್‌ಗಳೊಂದಿಗೆ ಸಮುದ್ರ ಸ್ಥಿತಿ ಮತ್ತು ಸುರಕ್ಷತಾ ಸಲಹೆ',
      'tabHome': 'ಮುಖಪುಟ', 'tabMap': 'ನಕ್ಷೆ', 'tabAi': 'AI ಏಜೆಂಟ್‌ಗಳು', 'tabAlerts': 'ಎಚ್ಚರಿಕೆಗಳು', 'tabNavigate': 'ಮಾರ್ಗ', 'tabInfo': 'ಮಾಹಿತಿ',
      'verdictGo': 'ಹೋಗಲು ಸುರಕ್ಷಿತ', 'verdictCaution': 'ಎಚ್ಚರಿಕೆ', 'verdictNoGo': 'ಅಪಾಯ — ಹೋಗಬೇಡಿ', 'verdictUnknown': 'ತಿಳಿದಿಲ್ಲ',
      'canIGoTitle': 'ಇಂದು ಸಮುದ್ರಕ್ಕೆ ಹೋಗಬಹುದೇ?', 'safeWindowLabel': 'ಸುರಕ್ಷಿತ ಸಮಯ', 'variablesTitle': 'ಪ್ರಸ್ತುತ ಸ್ಥಿತಿ',
      'alertsTitle': 'ಸಕ್ರಿಯ ಸಮುದ್ರ ಎಚ್ಚರಿಕೆಗಳು', 'navigateTitle': 'ಮಾರ್ಗ ಸುರಕ್ಷತೆ ಮತ್ತು ಭೂ ಪರಿಶೀಲನೆ', 'infoTitle': 'ವ್ಯವಸ್ಥೆ ಮತ್ತು ಡೇಟಾ ಸ್ಥಿತಿ',
      'save': 'ಉಳಿಸಿ', 'cancel': 'ರದ್ದು', 'retry': 'ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ', 'languageLabel': 'ಭಾಷೆ',
    },
    'ml': {
      'appTagline': 'സഹകരണ ഏജന്റുകളോടെയുള്ള സമുദ്രസ്ഥിതിയും സുരക്ഷാ ഉപദേശവും',
      'tabHome': 'ഹോം', 'tabMap': 'ഭൂപടം', 'tabAi': 'AI ഏജന്റുകൾ', 'tabAlerts': 'മുന്നറിയിപ്പുകൾ', 'tabNavigate': 'വഴി', 'tabInfo': 'വിവരം',
      'verdictGo': 'പോകുന്നത് സുരക്ഷിതം', 'verdictCaution': 'ജാഗ്രത', 'verdictNoGo': 'അപകടം — പോകരുത്', 'verdictUnknown': 'അജ്ഞാതം',
      'canIGoTitle': 'ഇന്ന് കടലിൽ പോകാമോ?', 'safeWindowLabel': 'സുരക്ഷിത സമയം', 'variablesTitle': 'നിലവിലെ സ്ഥിതി',
      'alertsTitle': 'സജീവ സമുദ്ര മുന്നറിയിപ്പുകൾ', 'navigateTitle': 'വഴി സുരക്ഷയും കര പരിശോധനയും', 'infoTitle': 'സിസ്റ്റവും ഡാറ്റ നിലയും',
      'save': 'സംരക്ഷിക്കുക', 'cancel': 'റദ്ദാക്കുക', 'retry': 'വീണ്ടും ശ്രമിക്കുക', 'languageLabel': 'ഭാഷ',
    },
    'ta': {
      'appTagline': 'கூட்டு முகவர்களுடன் கடல் நிலை மற்றும் பாதுகாப்பு ஆலோசனை',
      'tabHome': 'முகப்பு', 'tabMap': 'வரைபடம்', 'tabAi': 'AI முகவர்கள்', 'tabAlerts': 'எச்சரிக்கைகள்', 'tabNavigate': 'வழி', 'tabInfo': 'தகவல்',
      'verdictGo': 'செல்வது பாதுகாப்பானது', 'verdictCaution': 'எச்சரிக்கை', 'verdictNoGo': 'ஆபத்து — செல்ல வேண்டாம்', 'verdictUnknown': 'தெரியவில்லை',
      'canIGoTitle': 'இன்று கடலுக்குச் செல்லலாமா?', 'safeWindowLabel': 'பாதுகாப்பான நேரம்', 'variablesTitle': 'தற்போதைய நிலை',
      'alertsTitle': 'செயலில் உள்ள கடல் எச்சரிக்கைகள்', 'navigateTitle': 'வழிப் பாதுகாப்பு மற்றும் நிலச் சோதனை', 'infoTitle': 'அமைப்பு மற்றும் தரவு நிலை',
      'save': 'சேமி', 'cancel': 'ரத்து செய்', 'retry': 'மீண்டும் முயற்சி', 'languageLabel': 'மொழி',
    },
    'or': {
      'appTagline': 'ସହଯୋଗୀ ଏଜେଣ୍ଟମାନଙ୍କ ସହ ସାମୁଦ୍ରିକ ସ୍ଥିତି ଓ ସୁରକ୍ଷା ପରାମର୍ଶ',
      'tabHome': 'ମୁଖ୍ୟ', 'tabMap': 'ମାନଚିତ୍ର', 'tabAi': 'AI ଏଜେଣ୍ଟ', 'tabAlerts': 'ସତର୍କତା', 'tabNavigate': 'ମାର୍ଗ', 'tabInfo': 'ସୂଚନା',
      'verdictGo': 'ଯିବା ସୁରକ୍ଷିତ', 'verdictCaution': 'ସାବଧାନ', 'verdictNoGo': 'ବିପଦ — ଯାଆନ୍ତୁ ନାହିଁ', 'verdictUnknown': 'ଅଜଣା',
      'canIGoTitle': 'ଆଜି ସମୁଦ୍ରକୁ ଯାଇପାରିବି କି?', 'safeWindowLabel': 'ସୁରକ୍ଷିତ ସମୟ', 'variablesTitle': 'ବର୍ତ୍ତମାନ ସ୍ଥିତି',
      'alertsTitle': 'ସକ୍ରିୟ ସାମୁଦ୍ରିକ ସତର୍କତା', 'navigateTitle': 'ମାର୍ଗ ସୁରକ୍ଷା ଓ ସ୍ଥଳ ଯାଞ୍ଚ', 'infoTitle': 'ସିଷ୍ଟମ ଓ ଡାଟା ସ୍ଥିତି',
      'save': 'ସଂରକ୍ଷଣ', 'cancel': 'ବାତିଲ', 'retry': 'ପୁଣି ଚେଷ୍ଟା', 'languageLabel': 'ଭାଷା',
    },
    'bn': {
      'appTagline': 'সহযোগী এজেন্টের মাধ্যমে সামুদ্রিক অবস্থা ও নিরাপত্তা পরামর্শ',
      'tabHome': 'প্রধান', 'tabMap': 'মানচিত্র', 'tabAi': 'AI এজেন্ট', 'tabAlerts': 'সতর্কতা', 'tabNavigate': 'পথ', 'tabInfo': 'তথ্য',
      'verdictGo': 'যাওয়া নিরাপদ', 'verdictCaution': 'সাবধান', 'verdictNoGo': 'বিপদ — যাবেন না', 'verdictUnknown': 'অজানা',
      'canIGoTitle': 'আজ কি সমুদ্রে যেতে পারি?', 'safeWindowLabel': 'নিরাপদ সময়', 'variablesTitle': 'বর্তমান অবস্থা',
      'alertsTitle': 'সক্রিয় সামুদ্রিক সতর্কতা', 'navigateTitle': 'পথ নিরাপত্তা ও স্থল পরীক্ষা', 'infoTitle': 'সিস্টেম ও ডেটার অবস্থা',
      'save': 'সংরক্ষণ', 'cancel': 'বাতিল', 'retry': 'আবার চেষ্টা', 'languageLabel': 'ভাষা',
    },
  };

  String _value(String key, String fallback) => _values[language]?[key] ?? fallback;

  @override String get appTagline => _value('appTagline', super.appTagline);
  @override String get tabHome => _value('tabHome', super.tabHome);
  @override String get tabMap => _value('tabMap', super.tabMap);
  @override String get tabAi => _value('tabAi', super.tabAi);
  @override String get tabAlerts => _value('tabAlerts', super.tabAlerts);
  @override String get tabNavigate => _value('tabNavigate', super.tabNavigate);
  @override String get tabInfo => _value('tabInfo', super.tabInfo);
  @override String get verdictGo => _value('verdictGo', super.verdictGo);
  @override String get verdictCaution => _value('verdictCaution', super.verdictCaution);
  @override String get verdictNoGo => _value('verdictNoGo', super.verdictNoGo);
  @override String get verdictUnknown => _value('verdictUnknown', super.verdictUnknown);
  @override String get canIGoTitle => _value('canIGoTitle', super.canIGoTitle);
  @override String get safeWindowLabel => _value('safeWindowLabel', super.safeWindowLabel);
  @override String get variablesTitle => _value('variablesTitle', super.variablesTitle);
  @override String get alertsTitle => _value('alertsTitle', super.alertsTitle);
  @override String get navigateTitle => _value('navigateTitle', super.navigateTitle);
  @override String get infoTitle => _value('infoTitle', super.infoTitle);
  @override String get save => _value('save', super.save);
  @override String get cancel => _value('cancel', super.cancel);
  @override String get retry => _value('retry', super.retry);
  @override String get languageLabel => _value('languageLabel', super.languageLabel);
}
