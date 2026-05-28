# Daxelo Kinrel — Migration Documentation

Every migration MUST fill in this template before deployment.

## Template

```
Migration: <descriptive name>
Date: YYYY-MM-DD
Author: <name>

What changed:
- <bullet points of changes>

Why:
- <reason for the change>

Rollback steps:
1. <step-by-step rollback procedure>
2. ...

Flutter impact:
- <which API responses changed, if any>
- <which screens/features are affected>

Pre-migration checklist:
[ ] Backed up database (bash scripts/backup_db.sh)
[ ] Tested on staging
[ ] No column drops without deprecation period
[ ] API backward compatibility verified
[ ] Flutter app updated to handle new/changed fields
```

## Recent Migrations

### add_refresh_token
- Date: 2025-03-05
- Added refreshToken, refreshTokenExp, fcmToken to User model
- Switched from SQLite to PostgreSQL
- Rollback: Remove fields from User model, revert datasource to SQLite

### add_notification_log
- Date: 2025-03-05
- Added NotificationLog model for duplicate notification prevention
- Rollback: Drop NotificationLog table
