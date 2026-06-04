import 'package:flutter/material.dart';

class FamilyMember {
  final String id;
  final String name;
  final String role;
  final String nickname;
  final Offset position;
  final String? photoUrl;
  final bool isSelf;

  const FamilyMember({
    required this.id,
    required this.name,
    required this.role,
    required this.nickname,
    required this.position,
    this.photoUrl,
    this.isSelf = false,
  });
}

class FamilyConnection {
  final String fromId;
  final String toId;

  const FamilyConnection({required this.fromId, required this.toId});
}
