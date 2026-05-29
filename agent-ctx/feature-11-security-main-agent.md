# Feature 11: Security Infrastructure — Implementation Summary

## Task ID: feature-11-security
## Agent: main

## Files Created

### 1. `/home/z/my-project/server/prisma/rls-policies-v2.sql`
Complete Supabase Row Level Security policies for 24 tables:
- **User**: Own profile read/update/insert
- **Family**: Member-only view, owner/admin update, owner-only delete, link-mode discoverable
- **FamilyMember**: Family-member view, owner/admin insert/update/delete, owner self-removal prevention
- **Person**: Privacy-aware SELECT (public/family/extended levels), soft-delete handling, role-gated CUD
- **Relationship**: Family-member view, admin-only CUD
- **Invitation**: Multi-path access (family member, recipient, inviter)
- **FamilyInvite**: Family-member view, admin CUD
- **Notification**: Own-only access + system insert
- **NotificationUpdate**: Via notification ownership
- **PersonPrivacySetting**: Family-member view, admin update, member insert
- **DataAccessLog**: Admin-only view, system insert
- **PhotoConsent**: Family-member view, admin CUD
- **FamilyPost**: Family-member view, member+ insert, admin update/delete
- **GraphLayoutState**: Own-only access
- **GraphChangeLog**: Family-member view, system insert
- **Subscription/SupportTicket/SupportMessage**: Own-only access
- **NotificationPreference**: Own-only full CRUD
- **RefreshToken/FcmToken**: Own-only access + system insert
- **AuditLog**: Admin-only view, system insert
- **ApiKey**: Own-only full CRUD

Helper functions:
- `has_family_role(user_id, family_id, minimum_role)` — checks role hierarchy
- `can_access_person(user_id, person_id)` — privacy-aware person access check

### 2. `/home/z/my-project/server/src/common/guards/roles-v2.guard.ts`
Enhanced family-scoped role-based access guard:
- **4-role hierarchy**: owner (4) > admin (3) > member (2) > viewer (1)
- **FamilyRoles decorator**: `@FamilyRoles('owner', 'admin')` 
- **FamilyId extraction**: From params, query, or body
- **Prisma lookup**: Checks FamilyMember table for user's role
- **Hierarchical check**: Higher roles automatically satisfy lower requirements
- **Request enrichment**: Attaches `familyRole` and `familyId` to request
- **Utility exports**: `getRoleWeight()`, `hasMinimumRole()`

Usage pattern:
```typescript
@FamilyRoles('owner', 'admin')
@UseGuards(JwtAuthGuard, RolesV2Guard)
async createRelationship() { ... }
```

### 3. `/home/z/my-project/server/src/common/interceptors/secure-upload.interceptor.ts`
Secure file upload interceptor with comprehensive security:
- **MIME type validation**: Only jpeg, png, webp, gif allowed
- **Magic byte verification**: Prevents MIME spoofing attacks
- **File size limit**: 5 MB maximum
- **Filename sanitization**: Removes path traversal, special chars, length limit
- **Multi-size image generation** via Sharp:
  - thumb: 80×80 (cover crop, WebP quality 70)
  - card: 150×150 (cover crop, WebP quality 80)
  - full: 400×400 (fit inside, WebP quality 85)
- **Supabase Storage upload**: With CDN URL generation
- **EXIF metadata stripping**: For privacy
- **Content scanning**:
  - Filename pattern analysis
  - Tracking pixel detection (1×1 images)
  - Excessive dimension detection (DoS prevention)
  - Oversized EXIF data detection
  - Format mismatch detection
  - Shannon entropy analysis (steganography detection)
  - Buffer-to-pixel ratio analysis
- **Factory helper**: `createSecureFileInterceptor()` for Multer integration

## Dependencies Added
- `sharp` — Image processing library
- `@supabase/supabase-js` — Supabase Storage client

## Architecture Notes
- RLS policies use `auth.uid()::text` for UUID-to-text comparison with CUID IDs
- Role hierarchy weights enable O(1) permission checks
- The SecureUploadInterceptor works with NestJS's FileInterceptor pipeline
- Content scanning is extensible — can integrate with Google Vision/AWS Rekognition
- GIF files are handled specially (preserved for full, converted to WebP for thumbnails)
