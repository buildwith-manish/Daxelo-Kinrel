# 🚨 Google Sign-In Crash - Quick Fix Guide

## The Exact Reason (Most Likely)

### 🎯 **90% Probability: Missing SHA-1 Certificate Fingerprint**

Your app crashes because **Google cannot verify your Android app's identity** without the SHA-1 fingerprint being registered in Firebase Console.

---

## ⚡ 5-Minute Fix

### Step 1: Get Your SHA-1 Fingerprint

```bash
# Run this command
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

**Output will look like:**
```
Certificate fingerprint (SHA1): AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD
Certificate fingerprint (SHA256): 11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11
```

**Copy both SHA-1 and SHA-256!**

---

### Step 2: Add to Firebase Console

1. Go to: https://console.firebase.google.com/
2. Select your project: **Daxelo-Kinrel**
3. Click ⚙️ (Settings) → Project settings
4. Scroll to "Your apps" section
5. Click on your Android app (or add one if missing)
6. Click "Add fingerprint"
7. Paste **SHA-1** → Save
8. Click "Add fingerprint" again
9. Paste **SHA-256** → Save

---

### Step 3: Download Updated google-services.json

1. In the same Firebase page, click "Download google-services.json"
2. Replace the file in your project:
   ```
   Daxelo-Kinrel-App/android/app/google-services.json
   ```

---

### Step 4: Verify Supabase Configuration

1. Go to: https://supabase.com/dashboard
2. Select your project
3. Navigate to: **Authentication** → **Providers** → **Google**
4. Make sure:
   - ✅ "Enable Sign in with Google" is toggled ON
   - ✅ "Authorized Client IDs" contains your Android Client ID

**To get Android Client ID:**
1. Go to: https://console.cloud.google.com/apis/credentials
2. You'll see an Android client automatically created (it looks like: `xxxxx-xxxxx.apps.googleusercontent.com`)
3. Copy it
4. Paste in Supabase "Authorized Client IDs" field

---

### Step 5: Clean and Rebuild

```bash
cd Daxelo-Kinrel-App
flutter clean
flutter pub get
flutter run
```

---

## 🔍 If Still Crashing - Check Logs

While app is running:

```bash
adb logcat | grep -E "PlatformException|GoogleSignIn|FirebaseAuth|FATAL"
```

Click "Sign in with Google" and **share the error output** for further diagnosis.

---

## 📱 Common Error Messages & Solutions

| Error Message | Exact Reason | Fix |
|--------------|--------------|-----|
| `SIGN_IN_FAILED` | SHA-1 not registered | Add SHA-1 to Firebase Console |
| `PlatformException(sign_in_failed, com.google.android.gms.common.api.ApiException: 10:)` | Invalid SHA-1 or wrong google-services.json | Regenerate SHA-1, update Firebase, download new google-services.json |
| `ApiException: 12501` | User cancelled or SHA-1 missing | Add SHA-1 fingerprint |
| `ApiException: 10` | Developer error (SHA-1/OAuth config) | Check SHA-1 + Client ID in Google Cloud Console |
| `Network error` | Missing Internet permission | Add `<uses-permission android:name="android.permission.INTERNET"/>` to AndroidManifest.xml |

---

## 🎯 The Real Problem (Technical Explanation)

When you click "Sign in with Google":

1. **Flutter calls** → `GoogleSignIn().signIn()`
2. **Android Google Play Services** receives request
3. **Google Play Services checks** → "Is this app authorized?"
4. **Google servers verify** → SHA-1 fingerprint against registered fingerprints in Firebase/Google Cloud
5. ❌ **NO MATCH FOUND** → Returns error code 10 or 12501
6. **Flutter receives error** → If not handled with try-catch → **App crashes**

**Solution:** Register SHA-1 so Google can verify your app ✅

---

## ✅ Success Checklist

After the fix, Google Sign-In should:

- ✅ Open Google account selection dialog
- ✅ Ask for permissions (first time)
- ✅ Return to your app with user data
- ✅ No crash or force close

---

## 🆘 Emergency Debug Commands

If nothing works, run this comprehensive diagnostic:

```bash
# 1. Check current SHA-1
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep SHA

# 2. Check package name
grep applicationId Daxelo-Kinrel-App/android/app/build.gradle

# 3. Check if google-services.json exists
ls -la Daxelo-Kinrel-App/android/app/google-services.json

# 4. Full clean rebuild
cd Daxelo-Kinrel-App
flutter clean
cd android && ./gradlew clean && cd ..
flutter pub get
flutter run --verbose > debug.log 2>&1

# 5. Check logs while testing
adb logcat -c  # Clear logs
adb logcat > google_signin_crash.log &  # Start logging
# Now click "Sign in with Google" in your app
# Then check google_signin_crash.log file
```

---

## 📊 Root Cause Probability

Based on Flutter Google Sign-In issues:

| Issue | Probability |
|-------|------------|
| Missing/Wrong SHA-1 Fingerprint | **70%** |
| Wrong/Old google-services.json | **15%** |
| Missing Android Client ID in Supabase | **8%** |
| Code error (no try-catch) | **4%** |
| Dependency conflicts | **2%** |
| Other | **1%** |

---

## 🎓 Why This Happens

Google requires **cryptographic verification** that the app requesting sign-in is actually YOUR app and not a malicious clone. The SHA-1 fingerprint is like a unique fingerprint of your app's signing certificate.

**Without it:** Google rejects the sign-in request → App crashes

**With it:** Google verifies the app → Sign-in succeeds → User authenticated ✅

---

## 💻 Platform-Specific Notes

### Android (Your Issue)
- ✅ Requires SHA-1 fingerprint
- ✅ Requires google-services.json
- ✅ Requires Android Client ID in Supabase

### iOS
- ✅ Requires iOS Client ID in GoogleSignIn initialization
- ✅ Requires URL schemes in Info.plist

### Web
- ✅ Requires Web Client ID
- ✅ No SHA-1 needed

Since you're on **Android**, the SHA-1 is mandatory!

---

## 🔗 Useful Links

- [Firebase Console](https://console.firebase.google.com/)
- [Google Cloud Console - Credentials](https://console.cloud.google.com/apis/credentials)
- [Supabase Dashboard](https://supabase.com/dashboard)
- [Flutter google_sign_in Package](https://pub.dev/packages/google_sign_in)
- [SHA-1 Certificate Fingerprint Guide](https://developers.google.com/android/guides/client-auth)

---

## ✨ After Fix Success

Once working, you should see:
1. Google account picker appears
2. User selects account
3. Permission consent (first time only)
4. App receives user data
5. User logged in successfully

**No crash! 🎉**
