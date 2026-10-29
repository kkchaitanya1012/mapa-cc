# Mapa app

Flutter app for both roles: the caretaker (built for iPhone) and the recipient (Android).

## Setup

```
cp config.example.json config.local.json      # Supabase URL + anon key, API_BASE_URL (your machine's LAN IP for phones)
flutter pub get
flutter run --dart-define-from-file=config.local.json
flutter analyze && flutter test
```

## Android build (recipient)

Needs Firebase values for lock-screen calls (see `../CALLING.md`):

```
python3 tools/firebase_config.py ~/Downloads/google-services.json   # writes config.android.json
flutter build apk --release --dart-define-from-file=config.android.json
```

`API_BASE_URL` is baked in at build time, so rebuild when the server address changes.

## iPhone build (caretaker)

Free provisioning: open `ios/Runner.xcworkspace` in Xcode, pick your device and a personal team, run. The install expires after 7 days and has no push; alerts show in the app.

## Code map

- `lib/data/repo.dart`: single source of truth. Reads Supabase under row-level security, realtime plus resume and 20 s refresh keep it fresh.
- `lib/data/call.dart`: the recipient's side of a call (LiveKit).
- `lib/push/`: FCM, native lock-screen call, ringtone.
- `lib/screens/`: caretaker (`shell`, `today`, `person`, `alerts`, `chat`) and recipient (`idle`, `call_screens`) screens.
- Debug builds read the first route from a `mapa_route` file in the app's temp dir, for screenshots.
