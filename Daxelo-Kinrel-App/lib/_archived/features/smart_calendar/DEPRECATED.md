# Smart Calendar (Panchang) — DEPRECATED

**Status**: Dormant. Not routed. Not referenced from any live code.
**Last updated**: 2026-07-11
**Reason**: Built but never wired into the router. Festival data hardcoded for 2024-2029 (now stale). Live alternatives `/family/:id/calendar` and `/pulse/festivals` cover secular cases.
**Revival steps**:
1. Refresh festival data source (hardcoded list → API or computed Panchang).
2. Add route `/family/:id/smart-calendar` in `app_router.dart`.
3. Add tile in family detail screen under a "Cultural" section.
4. Gate behind a feature flag for staged rollout.
5. Move folder back to `lib/features/smart_calendar/`.
