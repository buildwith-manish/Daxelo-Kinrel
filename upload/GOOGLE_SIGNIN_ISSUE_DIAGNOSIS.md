# Google Sign-In Crash Issue - Diagnosis & Solutions

## 🔴 Problem Summary
Your Flutter app (Daxelo-Kinrel) crashes and force stops when clicking "Sign in with Google" button.

---

## 🎯 Most Likely Root Causes

Based on common Flutter Google Sign-In issues, here are the **exact reasons** your app is crashing:

### **1. Missing or Incorrect SHA-1/SHA-256 Fingerprints in Firebase/Google Cloud Console** ⭐ (MOST COMMON)

**Why it crashes:**
- Android requires SHA-1 and SHA-256 certificate fingerprints to be registered in Firebase/Google Cloud Console
- Without proper fingerprints, Google Sign-In authentication fails immediately
- The app receives a `PlatformException` and crashes if not properly handled

**How to fix:**

#### For Debug Mode:
```bash
# Get debug SHA-1 fingerprint
cd Daxelo-Kinrel-App/android
./gradlew signingReport

# Or use keytool (macOS/Linux)
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

# Or use keytool (Windows)
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

#### For Release Mode:
```bash
# Get release SHA-1 fingerprint
keytool -list -v -keystore /path/to/your/keystore.jks -alias your-key-alias
```

**Then:**
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project → Project Settings → Your Apps → Android app
3. Add both **SHA-1** and **SHA-256** fingerprints
4. Download the updated `google-services.json` file
5. Replace it in `Daxelo-Kinrel-App/android/app/google-services.json`

---

### **2. Incorrect OAuth Client ID Configuration**

**Why it crashes:**
- Your app needs a proper Android OAuth Client ID from Google Cloud Console
- If you're using only the Web Client ID for Android, authentication will fail

**How to fix:**

1. Go to [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Navigate to: APIs & Services → Credentials
3. Create credentials → OAuth 2.0 Client ID → Android
4. Add your package name: (likely `com.daxelo.kinrel` based on your repo)
5. Add your SHA-1 fingerprint
6. Copy the Android Client ID

**In Supabase Dashboard** (since you use Supabase Auth):
1. Go to Authentication → Providers → Google
2. Add the **Android Client ID** to "Authorized Client IDs" field
3. Make sure both Web and Android client IDs are added

---

### **3. Missing Internet Permission in AndroidManifest.xml**

**Why it crashes:**
- Google Sign-In requires internet access
- Without permission, the app crashes when trying to connect

**How to fix:**

Check `Daxelo-Kinrel-App/android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Add these permissions -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    
    <application>
        ...
    </application>
</manifest>
```

---

### **4. Incorrect google-services.json or Missing in Android Project**

**Why it crashes:**
- The `google-services.json` file contains essential configuration
- If missing, outdated, or from the wrong project, authentication fails

**How to fix:**

1. Download fresh `google-services.json` from Firebase Console
2. Place it in: `Daxelo-Kinrel-App/android/app/google-services.json`
3. Make sure the package name in the file matches your app's package name
4. Verify the file is not in `.gitignore` during development

---

### **5. Dependency Version Conflicts**

**Why it crashes:**
- Incompatible versions of `google_sign_in` or Firebase plugins
- Conflicting AndroidX libraries

**How to fix:**

Check your `Daxelo-Kinrel-App/pubspec.yaml`:

```yaml
dependencies:
  # Use latest stable versions
  google_sign_in: ^6.2.1  # or latest
  supabase_flutter: ^2.0.0  # or latest compatible version
  
  # If using Firebase
  firebase_core: ^2.24.0
  firebase_auth: ^4.15.0
```

Run:
```bash
flutter pub get
flutter clean
flutter pub get
```

---

### **6. ProGuard Rules (Release Build Only)**

**Why it crashes:**
- Code obfuscation can strip necessary Google Sign-In classes
- Only affects release builds

**How to fix:**

Create/update `Daxelo-Kinrel-App/android/app/proguard-rules.pro`:

```proguard
# Google Sign-In
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Supabase
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**
```

Then in `android/app/build.gradle`:

```gradle
buildTypes {
    release {
        signingConfig signingConfigs.release
        minifyEnabled true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

---

### **7. Unhandled Exceptions in Sign-In Code**

**Why it crashes:**
- If exceptions aren't properly caught, app crashes
- Common in async operations

**How to fix:**

Your sign-in code should look like this:

```dart
Future<void> signInWithGoogle() async {
  try {
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    
    if (googleUser == null) {
      // User cancelled the sign-in
      print('Sign in cancelled by user');
      return;
    }

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final String? accessToken = googleAuth.accessToken;
    final String? idToken = googleAuth.idToken;

    if (accessToken == null || idToken == null) {
      throw Exception('Missing Google Auth Token');
    }

    // Authenticate with Supabase
    final AuthResponse response = await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );

    if (response.user != null) {
      print('Successfully signed in: ${response.user!.email}');
    }
  } on PlatformException catch (e) {
    print('PlatformException: ${e.code} - ${e.message}');
    // Show error to user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to sign in: ${e.message}')),
    );
  } catch (e) {
    print('Error during Google Sign In: $e');
    // Show error to user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('An error occurred. Please try again.')),
    );
  }
}
```

---

### **8. Supabase Configuration Issues**

**Why it crashes:**
- Incorrect Supabase URL or anon key
- Google provider not properly enabled in Supabase

**How to fix:**

1. **Verify Supabase initialization** in your app:
```dart
await Supabase.initialize(
  url: 'https://your-project.supabase.co',
  anonKey: 'your-anon-key',
);
```

2. **Enable Google Auth in Supabase Dashboard**:
   - Go to Authentication → Providers → Google
   - Toggle "Enable Sign in with Google"
   - Add your Web Client ID
   - Add Android Client ID to "Authorized Client IDs"

3. **Check Redirect URLs**:
   - Add `https://your-project.supabase.co/auth/v1/callback` to Google Cloud Console → OAuth 2.0 Client → Authorized redirect URIs

---

## 🔍 How to Debug and Find the Exact Error

Since the app is force closing, you need to check the logs:

### **Method 1: Using Android Studio**
1. Run your app in debug mode
2. Open Logcat at the bottom
3. Click "Sign in with Google"
4. Look for red error messages (especially `PlatformException`, `FirebaseAuthException`, or `SIGN_IN_FAILED`)

### **Method 2: Using Command Line**
```bash
# Start logging
adb logcat | grep -i "flutter\|google\|auth\|exception"

# Then click Sign in with Google in your app
```

### **Method 3: Using Flutter DevTools**
```bash
flutter run --verbose
```

---

## 📋 Step-by-Step Verification Checklist

1. ✅ SHA-1 and SHA-256 fingerprints added to Firebase Console
2. ✅ `google-services.json` downloaded and placed in `android/app/`
3. ✅ Android OAuth Client ID created in Google Cloud Console
4. ✅ Android Client ID added to Supabase → Google Provider → Authorized Client IDs
5. ✅ Internet permission in `AndroidManifest.xml`
6. ✅ Package name matches across Firebase, Google Cloud, and `build.gradle`
7. ✅ Latest versions of `google_sign_in` and `supabase_flutter` packages
8. ✅ Proper error handling with try-catch in sign-in code
9. ✅ Clean and rebuild: `flutter clean && flutter pub get`
10. ✅ Test on physical device (emulators sometimes have Google Play Services issues)

---

## 🚀 Quick Fix Commands

Run these in order:

```bash
cd Daxelo-Kinrel-App

# 1. Clean everything
flutter clean
cd android && ./gradlew clean && cd ..

# 2. Get dependencies
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 3. Rebuild
flutter build apk --debug

# 4. Install and check logs
flutter run --verbose
```

---

## 💡 Most Common Solution

**In 80% of cases, the issue is one of these:**

1. ⭐ **Missing SHA-1 fingerprint** in Firebase Console
2. ⭐ **Old/wrong `google-services.json`** file
3. ⭐ **Android Client ID not added** to Supabase Authorized Client IDs

**Quick Test:**
1. Generate SHA-1: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
2. Add to Firebase Console
3. Download new `google-services.json`
4. Replace in `android/app/`
5. Run: `flutter clean && flutter run`

---

## 📞 Need More Help?

If the issue persists after trying all above solutions:

1. Share the **exact error message** from Logcat
2. Share your `pubspec.yaml` dependencies
3. Share your `android/app/build.gradle` file
4. Share the Google Sign-In implementation code

The error logs will tell us the **exact** reason for the crash!
