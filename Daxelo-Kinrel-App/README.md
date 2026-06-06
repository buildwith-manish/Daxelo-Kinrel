# DAXELO KINREL — Flutter App

Indian family relationship intelligence app built with Flutter.

## Tech Stack

- **Flutter** 3.8+ (Dart)
- **State Management**: Riverpod
- **Routing**: GoRouter
- **Auth**: Supabase Flutter SDK
- **Networking**: Dio
- **Storage**: Hive, flutter_secure_storage
- **Models**: Freezed + json_serializable
- **Env**: --dart-define (compile-time)

## Getting Started

### Prerequisites

- Flutter SDK 3.8+
- Dart SDK 3.0+

### Setup

1. Install dependencies:
   ```bash
   flutter pub get
   ```

2. Generate code (Freezed, json_serializable):
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

3. Run the app with --dart-define for credentials:
   ```bash
   flutter run \
     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=eyJ... \
     --dart-define=API_BASE_URL=https://api.example.com \
     --dart-define=GOOGLE_WEB_CLIENT_ID=xxx.apps.googleusercontent.com \
     --dart-define=GOOGLE_ANDROID_CLIENT_ID=xxx.apps.googleusercontent.com \
     --dart-define=GOOGLE_IOS_CLIENT_ID=xxx.apps.googleusercontent.com
   ```

### Web Build

```bash
flutter build web \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=API_BASE_URL=... \
  --dart-define=GOOGLE_WEB_CLIENT_ID=... \
  --dart-define=GOOGLE_ANDROID_CLIENT_ID=... \
  --dart-define=GOOGLE_IOS_CLIENT_ID=...
```

### Assets

- `assets/data/indian_kinship.json` — 523 Indian kinship relationships across 13 languages
- `assets/fonts/` — Outfit, DM Sans, DM Mono custom fonts
- `assets/icons/` — Brand SVG icons

## Project Structure

```
lib/
├── core/           # Config, constants, services, theme
│   ├── config/     # App config, env config
│   ├── constants/  # Brand colors, typography, spacing
│   ├── kinship/    # Kinship engine, models, providers
│   ├── graph/      # Family graph service
│   ├── networking/ # Dio client, API result
│   ├── routing/    # GoRouter configuration
│   ├── services/   # Supabase service
│   └── theme/      # App theme, theme provider
├── features/       # Feature modules
│   ├── auth/       # Sign in, sign up
│   ├── family/     # Family list, tree, path finder
│   ├── home/       # Home screen
│   ├── kinship/    # Kinship search & detail
│   ├── onboarding/ # Onboarding flow
│   ├── profile/    # User profile
│   ├── settings/   # App settings
│   └── splash/     # Splash screen
└── shared/         # Shared widgets & painters
```

## Features

- 🔐 Supabase Authentication (Email/Password)
- 👨‍👩‍👧‍👦 Family Tree Visualization
- 🔍 Kinship Path Finder
- 🇮🇳 523 Indian Kinship Terms (13 Languages)
- 🎨 Kinrel Brand Design System
- 📱 Cross-platform (Android, iOS, Web)
