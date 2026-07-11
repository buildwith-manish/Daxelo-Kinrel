// lib/features/family_map/helpers/location_permission_helper.dart
//
// DAXELO KINREL — Location Permission Helper
//
// Handles the GPS permission flow for the Family Map's live location
// sharing feature. Never enables sharing without an actual granted
// permission — no optimistic UI.

import 'package:geolocator/geolocator.dart';

/// Result of a permission request attempt.
enum PermissionResult {
  /// Permission granted (whileInUse or always).
  granted,
  /// Permission denied — user can try again.
  denied,
  /// Permission permanently denied — must open app settings.
  deniedForever,
  /// Location services disabled on the device.
  serviceDisabled,
}

/// Check and request location permission.
///
/// Flow:
/// 1. Check if location services are enabled. If not → [serviceDisabled].
/// 2. Check current permission. If already granted → [granted].
/// 3. If denied (not forever), request permission. If granted → [granted].
/// 4. If deniedForever, return [deniedForever] — caller should call
///    [openAppSettings] to let the user fix it manually.
///
/// Never returns [granted] without an actual permission being confirmed.
Future<PermissionResult> requestLocationPermission() async {
  // 1. Check location services
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return PermissionResult.serviceDisabled;
  }

  // 2. Check current permission
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always) {
    return PermissionResult.granted;
  }

  // 3. Request permission if not permanently denied
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      return PermissionResult.granted;
    }
    if (permission == LocationPermission.deniedForever) {
      return PermissionResult.deniedForever;
    }
    return PermissionResult.denied;
  }

  // 4. Already deniedForever
  return PermissionResult.deniedForever;
}

/// Open the device's app settings so the user can grant location
/// permission manually after denying it permanently.
Future<void> openLocationSettings() async {
  await Geolocator.openAppSettings();
}

/// Get a single GPS position. Call only after permission is granted.
/// Uses medium accuracy with a 5s timeout — fast enough for a one-shot
/// fix without draining battery.
Future<Position?> getCurrentPosition() async {
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 5),
      ),
    );
  } catch (e) {
    return null;
  }
}
