import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class FamilyMember {
  final String id;
  final String name;
  final String role;
  final String nickname;
  final Offset position;
  final String? photoUrl;
  final bool isSelf;
  final double nodeScale; // 1.0 = normal, 1.15 = grandparent larger

  // Loaded image — populated at runtime by FamilyTreeScreen
  ui.Image? loadedImage;

  FamilyMember({
    required this.id,
    required this.name,
    required this.role,
    required this.nickname,
    required this.position,
    this.photoUrl,
    this.isSelf = false,
    this.nodeScale = 1.0,
  });
}

class FamilyConnection {
  final String fromId;
  final String toId;
  const FamilyConnection({required this.fromId, required this.toId});
}
