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
- **Env**: flutter_dotenv

## Getting Started

### Prerequisites

- Flutter SDK 3.8+
- Dart SDK 3.0+

### Setup

1. Copy `.env.example` to `.env` and fill in your credentials:
   ```bash
   cp .env.example .env
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Generate code (Freezed, json_serializable):
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. Run the app:
   ```bash
   flutter run
   ```

### Web Build

```bash
flutter build web
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
