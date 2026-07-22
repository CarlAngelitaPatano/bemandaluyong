# Be@Mandaluyong

A Flutter civic/tourism app for Mandaluyong City, Philippines.

## Features

- **Heritage Church Trail** — visit and verify heritage churches around the city to earn a completion certificate (emailed via EmailJS), with unlockable achievement badges along the way.
- **Heritage in 3D / AR** — a 3D/AR model viewer preview for select heritage sites.
- **Local news** — live headlines pulled from Google News RSS.
- **City services & events** — directory of city government services and upcoming events.
- **Attractions** — points of interest around Mandaluyong.
- **Homegrown** — a directory of local businesses and eateries.
- **Weather** — live conditions via Open-Meteo.
- **Profile & auth** — email/password, Google Sign-In, and phone sign-in via Firebase Authentication.
- **Notifications** — an in-app notification center plus a daily 7:00 AM local reminder.

## Getting started

```
flutter pub get
flutter run
```

Android is the primary target (launcher icon and splash screen are configured for Android only; iOS/web are disabled in `pubspec.yaml`).

### Useful commands

```
flutter analyze                     # static analysis
flutter test                        # run all tests
flutter build apk                   # release Android APK
flutter build appbundle             # release Android App Bundle (Play Store)
```

## Tech notes

- No custom backend — content is either hardcoded in the relevant feature file or fetched live from free, keyless public APIs (Open-Meteo, Google News RSS, OpenStreetMap tiles).
- Firebase is used only for Authentication.
- Local state (theme, trail progress, notifications, onboarding) is persisted with `shared_preferences`.

See `CLAUDE.md` for detailed architecture notes.
