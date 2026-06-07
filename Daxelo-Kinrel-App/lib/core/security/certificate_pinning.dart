// lib/core/security/certificate_pinning.dart
//
// DAXELO KINREL — Certificate Pinning Utility
//
// Provides infrastructure for SSL certificate pinning in production.
// Certificate pinning validates that the server's SSL certificate matches
// a known fingerprint, preventing MITM attacks even if a CA is compromised.
//
// SETUP:
// 1. Get your production server's certificate SHA-256 fingerprint:
//    `openssl s_client -connect daxelo-kinrel-server.onrender.com:443 \
//     | openssl x509 -fingerprint -sha256`
// 2. Add the fingerprint to [productionFingerprints]
// 3. Call [configureCertificatePinning(dio)] during app initialization
//
// NOTE: When certificates are renewed, fingerprints must be updated here
// and a new app version released. Consider using backup fingerprints
// during certificate rotation periods.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Production certificate SHA-256 fingerprints.
/// Update when SSL certificates are renewed.
const Set<String> productionFingerprints = {
  // Add your production server's SHA-256 certificate fingerprint here.
  // Example: 'a1b2c3d4e5f6789...'
  //
  // To get the fingerprint:
  // openssl s_client -connect daxelo-kinrel-server.onrender.com:443 \
  //   2>/dev/null | openssl x509 -fingerprint -sha256 -noout
  //
  // Remove colons and convert to lowercase for the hex string.
};

/// Whether certificate pinning should be active.
/// Only enabled in release builds with configured fingerprints.
bool get certificatePinningEnabled =>
    kReleaseMode && productionFingerprints.isNotEmpty;

/// Configures certificate pinning on a Dio instance.
/// No-op if pinning is not enabled (development or no fingerprints).
void configureCertificatePinning(Dio dio) {
  if (!certificatePinningEnabled) return;

  // NOTE: Full certificate pinning requires the `dio_certificate_pinning`
  // package or a custom HTTP client adapter. This is a placeholder that
  // adds the infrastructure for when the package is added.
  //
  // To complete implementation:
  // 1. Add `dio_certificate_pinning: ^2.0.0` to pubspec.yaml
  // 2. Import and configure:
  //    dio.httpClientAdapter = CertificatePinningInterceptor(
  //      allowedSHAFingerprints: productionFingerprints.toList(),
  //    );

  debugPrint(
    '🔒 Certificate pinning: infrastructure ready, '
    'fingerprints not yet configured',
  );
}
