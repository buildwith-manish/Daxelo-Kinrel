# Daxelo-Kinrel Flutter App — v3.1

Flutter client for the Daxelo-Kinrel Deterministic Kinship Engine v3.0 spec, with v3.1 `temporal` field extension.

## File Structure (spec §18)

```
lib/
├── core/
│   └── services/
│       └── relationship_engine.dart    # Offline mirror of server engine
├── data/
│   └── drift/
│       └── app_database.dart           # Offline SQLite schema (4 edge types only)
└── features/
    └── family/
        └── presentation/
            └── widgets/
                └── relationship_suggestion_sheet.dart   # Spec §10 auto-detect UI
```

## Architecture

The Flutter app mirrors the server's deterministic algorithm 1:1 so it works **fully offline**. When online, it delegates to the server for authoritative answers and queues mutations for sync.

```
User long-press A → Tap "Relate to" → Tap B
       ↓
RelationshipEngine.resolveSignature()  ← local BFS depth 8
       ↓
VocabularyMapper.resolve()             ← local 9,552-row asset JSON
       ↓
RelationshipSuggestionSheet            ← show "Detected: [Term]" or manual picker
       ↓
User confirms → Drift SQLite insert (4 edge types only)
       ↓
Background sync → POST /relationships (when online)
```

## Setup

```bash
cd /home/z/my-project/repos/daxelo-kinrel-app

# 1. Install deps
flutter pub get

# 2. Generate Drift code (creates app_database.g.dart)
dart run build_runner build --delete-conflicting-outputs

# 3. Bundle the vocabulary as an asset
cp /home/z/my-project/download/daxelo_kinrel_vocabulary.json assets/vocabulary.json

# 4. Run
flutter run
```

## Offline Vocabulary Loading

On startup, the app loads `assets/vocabulary.json` and feeds it to `VocabularyMapper.loadAll()`. The mapper builds an in-memory index keyed by `signatureKey|languageCode` for O(1) primary lookup. Memory footprint: ~12MB for all 9,552 rows; can be sliced by language to reduce to ~500KB per language.

```dart
final mapper = ref.read(vocabularyMapperProvider);
final jsonStr = await rootBundle.loadString('assets/vocabulary.json');
final data = json.decode(jsonStr);
mapper.loadAll((data['rows'] as List).cast<Map<String, dynamic>>());
```

## Auto-Detect Workflow (spec §10)

The `RelationshipSuggestionSheet` widget implements the full workflow:

1. **Detection succeeded with fundamental edge** → show "Detected: [Term]" + Confirm button.
2. **Detection succeeded but term is DERIVED** → show missing-edge card asking user to confirm the fundamental edge that produces the derived label (spec §8.2).
3. **Detection failed (insufficient graph info)** → show manual picker with only the 4 fundamental options (parent, spouse, adoptive_parent, step_parent).

No repeated node pickers. No duplicate confirmation screens. One sheet, one round-trip.

## Sync (when online)

When the device comes online, queued mutations are pushed to the server:

```dart
final queue = await db.getPendingMutations();
for (final m in queue) {
  await http.post('/relationships', body: m.toJson());
  await db.markSynced(m.id);
}
```

The server is the source of truth — on conflict, server wins.
