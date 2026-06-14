# Contributing to Daxelo Kinrel

Thank you for your interest in contributing! This guide will help you get set up and follow our conventions.

## Setup

### Prerequisites

- **Node.js** 22+ and **npm** (or **Bun** 1.2+)
- **Flutter** 3.44+ with **Dart** 3.12+
- **PostgreSQL** (provided via Supabase)
- **Redis** 7+ (for session caching)
- **Git** 2.40+

### Backend (NestJS)

1. Clone the repo
2. Copy `.env.example` → `.env` in the repo root and fill in all values
3. Run `cd server && npm install`
4. Run `npx prisma generate`
5. Run `npx prisma migrate dev`
6. Run `npx prisma db seed` (optional — creates demo data)
7. Run `npm run start:dev`

### Flutter App

1. Copy `Daxelo-Kinrel-App/.env.example` → `Daxelo-Kinrel-App/.env` and fill in values
2. Run `cd Daxelo-Kinrel-App && flutter pub get`
3. Run `dart run build_runner build --delete-conflicting-outputs`
4. Run `flutter run`

### Quick Setup Script

```bash
chmod +x scripts/dev-setup.sh
./scripts/dev-setup.sh
```

## Branching

| Branch | Purpose |
|--------|---------|
| `main` | Production — deployed automatically |
| `dev` | Staging — integration testing |
| `feature/xyz` | Feature branches — created from `dev` |
| `fix/xyz` | Bug fix branches — created from `main` or `dev` |
| `docs/xyz` | Documentation changes |

### Workflow

1. Create a branch from `dev` (or `main` for hotfixes)
2. Make your changes with clear, atomic commits
3. Push and open a Pull Request against `dev`
4. Ensure CI passes (lint, build, test)
5. Request review from a maintainer
6. Squash-merge after approval

## Commit Format

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description

feat(auth): add 2FA challenge token flow
fix(graph): limit recursive CTE depth to prevent OOM
docs(readme): add API rate limits section
chore(deps): update @nestjs/common to 11.x
refactor(auth): extract password verify to shared method
test(families): add unit tests for createFamily
```

### Types

| Type | Usage |
|------|-------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no logic change |
| `refactor` | Code restructuring, no behavior change |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Build, deps, tooling |
| `ci` | CI/CD changes |

## Code Style

### Backend (TypeScript / NestJS)

- **Strict mode** — no `any` types without explicit justification
- **ESLint** — run `npm run lint` before committing
- **Prettier** — formatting is enforced
- **Imports** — use absolute paths with `@/` alias where configured
- **Services** — keep controllers thin; business logic belongs in services
- **DTOs** — always validate input with class-validator decorators
- **Error handling** — use NestJS built-in exceptions (`NotFoundException`, etc.)

### Flutter (Dart)

- **Strict types** — enable `strict-inference` and `strict-raw-types`
- **Lint** — run `flutter analyze` before committing; zero warnings required
- **Theme** — use `DKColors.isLight(context)` for theme-aware colors
- **State** — use Riverpod providers; avoid `setState` for complex state
- **Models** — match backend field names (`englishTerm`, `relationshipKey`, `relationshipCategory`)

### Flutter State Management (Riverpod) — ADR-006

**This rule is binding on all agents.** See `docs/adr/ADR-006-riverpod-read-vs-watch.md` for full rationale.

- **`ref.watch()` MUST be used** for all state consumed during rendering (inside `build()`, getters called from `build()`, or any method in the build path). This ensures the widget rebuilds when provider state changes.
- **`ref.read()` is ONLY permitted** inside event handlers (`onPressed`, `onTap`, callbacks), `initState`, `dispose`, async callbacks (post-`await`), and notifier mutations (`ref.read(provider.notifier).update(...)`).
- **NEVER use `ref.read()` inside `build()`** or any method/getter called from `build()`. This creates stale state — the widget will not rebuild when the provider changes.
- **Lint comment**: All `ConsumerWidget` and `ConsumerStatefulWidget` classes must include this comment:

```dart
/// Riverpod Usage (ADR-006):
///   - ref.watch(): used in build() for reactive state (UI rebuilds on change)
///   - ref.read(): used ONLY in event handlers, initState, dispose,
///     and notifier mutations (never in build path)
```

**Common mistake**: Calling `ref.read()` in a getter that is accessed during `build()`. The getter is part of the build path, so it must use `ref.watch()`.

**Fix pattern**: If you need a one-time side effect during build (e.g., analytics tracking), wrap it in `WidgetsBinding.instance.addPostFrameCallback((_) { ref.read(provider).track(); })` to move it out of the build frame.

## PR Checklist

Before submitting a Pull Request, verify:

- [ ] **Tests added/updated** — all existing and new tests pass
- [ ] **No new `any` types** — use proper TypeScript/Dart types
- [ ] **No secrets in code** — use environment variables, update `.env.example`
- [ ] **`.env.example` updated** — if new env vars were added
- [ ] **Lint passes** — `npm run lint` (backend) and `flutter analyze` (app)
- [ ] **Documentation updated** — README, JSDoc, or inline comments as needed
- [ ] **Breaking changes documented** — note in PR description and migration steps
- [ ] **No `ref.read()` in build path** — Riverpod `ref.read()` must not appear inside `build()`, getters, or methods called from `build()` (ADR-006)

## Project Structure

```
Daxelo-Kinrel/
├── Daxelo-Kinrel-App/     Flutter app
│   ├── lib/
│   │   ├── core/          Database, services, networking, theme
│   │   ├── features/      Feature modules (auth, family, kinship)
│   │   └── shared/        Shared widgets & painters
│   └── test/              Unit & widget tests
│
├── server/                NestJS backend (28 modules)
│   ├── src/modules/       Feature modules
│   ├── src/common/        Guards, interceptors, decorators
│   ├── prisma/            Prisma schema & migrations
│   └── scripts/           Backup, restore, cron scripts
│
├── deploy/                Deployment configs
├── .github/workflows/     CI/CD (7 workflows)
└── .env.example           Environment variable reference
```

## Getting Help

- Open a GitHub Issue for bugs or feature requests
- Check existing issues before creating new ones
- Tag maintainers for urgent production issues
