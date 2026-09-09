# ORCA Flutter App (orca_flutter/)

SIH 2026 · ISRO PS SIH26176 — fishermen-first Android app.
**Plan: ../docs/FLUTTER-PLAN.md (§1–§10). Theme: white + teal (original reference, locked).**
**Backend: sister repo [SangamSitapuri07/ORCA-backend](https://github.com/SangamSitapuri07/ORCA-backend) —
wahan `uvicorn backend.main:app --host 0.0.0.0 --port 8000` chalao.**

## D1 status (DONE in code)

- bottom-nav 5 tabs (मुखपृष्ठ · नक्शा · नेविगेट · **SOS (hamesha red)** · जानकारी)
- 3 display modes: **Light (white, default)** / Dark / Dhoop — 1-tap cycle in StatusStrip
- zoom in/out A−/A+ (0.85×–1.75×, persisted)
- first-launch language picker + **11/11 COMPLETE language JSONs** (`assets/i18n/`) + 1-tap 🌐 switch
- StatusStrip (online/offline live), Info tab (language grid, modes, zoom, translator card, backend URL editor + live `/health` check, ईमानदारी Charter)
- API client (real endpoints only): `/health`, `/api/v1/advisory`, `/api/v1/field`, `/api/v1/route-check`
- Screens D2–D6 ke liye honest stubs hain ("coming soon" chip) — koi fake data NAHI.

## Laptop pe run karne ke steps (Pehli baar)

```powershell
cd orca_flutter
flutter create . --org in.sih2026 --project-name orca_marine   # android/ platform files generate karega
flutter pub get
flutter run            # phone USB + debugging on
```

Baad mein APK share karne ke liye: `flutter build apk --debug`
(release: `flutter build apk --release` — D7 pe)

## flutter create ke BAAD — 2 zaroori manual steps

**1. `test/widget_test.dart` DELETE karo** (flutter create ka default counter-app
test hai, humare app ka nahi — delete na kiya to `flutter analyze` / `flutter test`
fail karega). Humara apna real test: `test/marine_test.dart` (run: `flutter test`).

**2. `android/app/src/main/AndroidManifest.xml` mein `<manifest>` tag ke ANDAR
sabse upar ye permissions paste karo** (location/SMS/notification/sensors):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.SEND_SMS"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-feature android:name="android.hardware.telephony" android:required="false"/>
```

Aur `<application>` tag mein yeh do attributes set karo:
`android:label="ORCA"` aur **`android:usesCleartextTraffic="true"`**
(Android 9+ default HTTP block karta hai — laptop backend http:// hai,
yeh nahi dala to har API call fail hoga. Pura ready-made manifest
chat/mail se paste kar lo, phir bas `flutter run`.)

**3. `android/build.gradle` ke BILKUL END mein (kisi `{ }` block ke ANDAR nahi,
file ki aakhri line ke baad) yeh paste karo** — `telephony 0.2.0` purana hai,
AGP 8 har plugin se `namespace` maangta hai; yeh guard usse inject kar deta hai
(warna "Could not create an instance of type ... LibraryVariantBuilderImpl /
Namespace not specified" aata hai):

```gradle
// telephony (SOS SMS) — AGP8 namespace guard
subprojects {
    afterEvaluate { project ->
        if (project.name == 'telephony' && project.hasProperty('android')) {
            project.android.namespace = 'com.shounakmulay.telephony'
        }
    }
}
```
**4. `android/app/build.gradle(.kts)` mein core library desugaring ON** —
`flutter_local_notifications 17` AGP 8 pe `checkDebugAarMetadata` fail
karta hai ("requires core library desugaring"). Dono flavours:

- **Groovy** (`build.gradle`): `compileOptions {` ke andar
  `coreLibraryDesugaringEnabled = true` aur file end mein:
  `dependencies { coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4' }`
- **Kotlin DSL** (`build.gradle.kts`): `isCoreLibraryDesugaringEnabled = true`
  aur `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`



## Notes

- Backend: laptop pe `uvicorn` chalu → dono same WiFi → Info tab mein laptop ka IPv4 `IP:8000` daal ke Check dabao.
- i18n: naya string hamesha `assets/i18n/*.json` ke GYARAH files mein ek saath — koi bhasha kabhi peeche nahi rehti.
- `telephony` package "discontinued" dikhta hai pub pe — kaam karta hai (SOS SMS ke liye use ho raha); agar kabhi issue aaye to alternate `flutter_sms`/`sms_advanced` easily swap ho jaayega (ek hi file `lib/screens/sos.dart` mein).
