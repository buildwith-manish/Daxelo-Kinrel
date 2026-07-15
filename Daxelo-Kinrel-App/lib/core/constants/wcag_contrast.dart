// lib/core/constants/wcag_contrast.dart
//
// DAXELO KINREL — WCAG Color Contrast Utility (P4.6)
//
// Pure-Dart implementation of the WCAG 2.1 contrast ratio formula.
// Uses dart:math for accurate pow/exp.
//
// Used by the P4.6 contrast test suite to verify all text/background
// pairs meet WCAG AA (4.5:1) or AAA (7:1).

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Computes the WCAG 2.1 contrast ratio between two colors.
///
/// Returns a ratio from 1.0 (identical colors) to 21.0 (black vs white).
double contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Returns true if [foreground] on [background] meets WCAG AA (4.5:1).
bool meetsWCAGAA(Color foreground, Color background) {
  return contrastRatio(foreground, background) >= 4.5;
}

/// Returns true if [foreground] on [background] meets WCAG AAA (7:1).
bool meetsWCAGAAA(Color foreground, Color background) {
  return contrastRatio(foreground, background) >= 7.0;
}

double _relativeLuminance(Color color) {
  // In Flutter 3.44+, Color.r/g/b return doubles in [0.0, 1.0].
  final r = _channelLuminance(color.r);
  final g = _channelLuminance(color.g);
  final b = _channelLuminance(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _channelLuminance(double channel) {
  if (channel <= 0.03928) return channel / 12.92;
  return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}
