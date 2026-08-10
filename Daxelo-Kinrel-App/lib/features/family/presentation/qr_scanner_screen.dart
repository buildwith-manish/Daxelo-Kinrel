// lib/features/family/presentation/qr_scanner_screen.dart
//
// DAXELO KINREL — QR Scanner Screen
//
// Uses mobile_scanner to scan a QR code containing a Kinrel join URL.
// Expected URL format: https://kinrel.app/join/<familyId>
// On successful scan, navigates to the Join Family screen with the
// family ID pre-filled.
//
// Gated behind kEnableQrJoin (default false).

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import 'join_family_screen.dart';
import 'package:go_router/go_router.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _hasScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: KinrelColors.textWhite),
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
        ),
        title: Text(
          'Scan QR Code',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Scanner view
          MobileScanner(
            onDetect: (capture) {
              if (_hasScanned) return;
              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;

              final rawValue = barcodes.first.rawValue;
              if (rawValue == null || rawValue.isEmpty) return;

              _hasScanned = true;

              // Parse the QR value: https://kinrel.app/join/<familyId>
              String? familyId;
              final uri = Uri.tryParse(rawValue);
              if (uri != null && uri.pathSegments.length >= 2) {
                if (uri.pathSegments[0] == 'join') {
                  familyId = uri.pathSegments[1];
                }
              }

              // Also accept raw family IDs
              familyId ??= rawValue;

              // Haptic + navigate
              Navigator.of(context).pop(familyId);
            },
          ),

          // Overlay frame
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: KinrelColors.orange,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Instructions
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Point the camera at a Kinrel family QR code',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textSilver,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
