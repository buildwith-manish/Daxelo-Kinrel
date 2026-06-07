# Kinship Data Assets

This directory contains the kinship JSON data files that were previously
bundled inside the Flutter app's `assets/data/global/` directory.

## Background

The Flutter app had 6 large JSON files totalling ~165 MB bundled in the APK:

| File | Size |
|------|------|
| `arabic_kinship_production.json` | 43.9 MB |
| `korean_kinship_production.json` | 41.0 MB |
| `japanese_kinship_production.json` | 26.9 MB |
| `vietnamese_kinship_production_v2.json` | 19.5 MB |
| `russian_kinship_production_v2.json` | 19.6 MB |
| `chinese_kinship_production.json` | 14.5 MB |

The Google Play Store has a 100 MB hard limit on APK size. These files
pushed the APK well over that limit, preventing the app from being
published.

## Solution (NEW-01)

Starting with V3 Phase 1, these files are served on demand from the
NestJS backend via the `GET /api/v1/kinship/data/:languageCode` endpoint.

The Flutter app's `KinshipLoaderService` downloads kinship data lazily
when a user selects a culture, and caches it to the device's filesystem
for offline reuse.

The Indian kinship data (`indian_kinship.json`) remains bundled since
it's the primary market — Indian languages must work offline.

## Deployment Instructions

1. **Copy the production JSON files** into this directory:

   ```bash
   # From the repository root or wherever the original files are stored
   cp arabic_kinship_production.json    server/kinship-assets/
   cp korean_kinship_production.json    server/kinship-assets/
   cp japanese_kinship_production.json  server/kinship-assets/
   cp vietnamese_kinship_production_v2.json server/kinship-assets/
   cp russian_kinship_production_v2.json    server/kinship-assets/
   cp chinese_kinship_production.json   server/kinship-assets/
   ```

2. **Set KINSHIP_DATA_DIR** (optional): If the data files are stored
   elsewhere on the production server, set the `KINSHIP_DATA_DIR`
   environment variable to the absolute path of the directory containing
   the JSON files. Defaults to `<cwd>/kinship-assets`.

3. **Verify**: After deployment, check the listing endpoint:

   ```bash
   curl https://api.kinrel.app/api/v1/kinship/data
   ```

   Should return:

   ```json
   {
     "availableLanguages": ["arabic", "korean", "japanese", "vietnamese", "russian", "chinese"],
     "totalSizeMB": 165.4
   }
   ```

4. **CDN**: In production, consider placing a CDN (Cloudflare, CloudFront)
   in front of the `/api/v1/kinship/data/` endpoint for faster global
   delivery and reduced server load. The endpoint sets `Cache-Control:
   public, max-age=86400` to enable CDN caching.

## Security

- Language codes are validated against a whitelist to prevent directory
  traversal attacks
- The endpoint is marked `@Public()` (no auth required) since kinship
  data is not user-specific — it's a shared cultural dictionary
- `X-Content-Type-Options: nosniff` is set on all responses
