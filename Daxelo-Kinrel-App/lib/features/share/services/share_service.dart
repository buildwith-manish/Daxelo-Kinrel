// lib/features/share/services/share_service.dart
//
// DAXELO KINREL — Share API Service
//
// Calls the NestJS share backend endpoints.
// Uses the shared dioProvider for authenticated HTTP requests.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/dio_client.dart';

// ═══════════════════════════════════════════════════════════════════════
// API Response Models
// ═══════════════════════════════════════════════════════════════════════

class ShareableLinkModel {
  const ShareableLinkModel({
    required this.id,
    required this.token,
    required this.cardType,
    this.familyId,
    this.personId,
    required this.title,
    this.description,
    required this.deepLinkUrl,
    this.viewCount = 0,
    this.shareCount = 0,
    this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String token;
  final String cardType;
  final String? familyId;
  final String? personId;
  final String title;
  final String? description;
  final String deepLinkUrl;
  final int viewCount;
  final int shareCount;
  final DateTime? expiresAt;
  final DateTime createdAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory ShareableLinkModel.fromJson(Map<String, dynamic> json) {
    return ShareableLinkModel(
      id: json['id'] as String,
      token: json['token'] as String,
      cardType: json['cardType'] as String,
      familyId: json['familyId'] as String?,
      personId: json['personId'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      deepLinkUrl: json['deepLinkUrl'] as String? ?? '',
      viewCount: json['viewCount'] as int? ?? 0,
      shareCount: json['shareCount'] as int? ?? 0,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class SharedCardModel {
  const SharedCardModel({
    required this.id,
    required this.token,
    required this.cardType,
    required this.title,
    this.description,
    required this.deepLinkUrl,
    this.viewCount = 0,
    this.shareCount = 0,
    this.family,
    this.person,
    this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String token;
  final String cardType;
  final String title;
  final String? description;
  final String deepLinkUrl;
  final int viewCount;
  final int shareCount;
  final Map<String, dynamic>? family;
  final Map<String, dynamic>? person;
  final DateTime? expiresAt;
  final DateTime createdAt;

  factory SharedCardModel.fromJson(Map<String, dynamic> json) {
    return SharedCardModel(
      id: json['id'] as String,
      token: json['token'] as String,
      cardType: json['cardType'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      deepLinkUrl: json['deepLinkUrl'] as String? ?? '',
      viewCount: json['viewCount'] as int? ?? 0,
      shareCount: json['shareCount'] as int? ?? 0,
      family: json['family'] as Map<String, dynamic>?,
      person: json['person'] as Map<String, dynamic>?,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class ShareStatsModel {
  const ShareStatsModel({
    required this.id,
    required this.token,
    required this.cardType,
    required this.title,
    this.viewCount = 0,
    this.shareCount = 0,
    this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String token;
  final String cardType;
  final String title;
  final int viewCount;
  final int shareCount;
  final DateTime? expiresAt;
  final DateTime createdAt;

  factory ShareStatsModel.fromJson(Map<String, dynamic> json) {
    return ShareStatsModel(
      id: json['id'] as String,
      token: json['token'] as String,
      cardType: json['cardType'] as String,
      title: json['title'] as String,
      viewCount: json['viewCount'] as int? ?? 0,
      shareCount: json['shareCount'] as int? ?? 0,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ShareService — API calls
// ═══════════════════════════════════════════════════════════════════════

class ShareService {
  ShareService(this._ref);
  final Ref _ref;

  static const _basePath = '/share';

  /// Create a new shareable link.
  Future<ShareableLinkModel> createShareableLink({
    required String cardType,
    required String title,
    String? familyId,
    String? personId,
    String? description,
    String? deepLinkUrl,
    int? expiresInDays,
  }) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post(_basePath, data: {
      'cardType': cardType,
      'title': title,
      if (familyId != null) 'familyId': familyId,
      if (personId != null) 'personId': personId,
      if (description != null) 'description': description,
      if (deepLinkUrl != null) 'deepLinkUrl': deepLinkUrl,
      if (expiresInDays != null) 'expiresInDays': expiresInDays,
    });
    return ShareableLinkModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Track a share event (increment shareCount).
  Future<Map<String, dynamic>> trackShare({required String token}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('$_basePath/track', data: {
      'token': token,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Get share stats by token.
  Future<ShareStatsModel> getShareStats({required String token}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get(_basePath, queryParameters: {'token': token});
    return ShareStatsModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get shared card data (public, no auth required).
  Future<SharedCardModel> getSharedCard({required String token}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('$_basePath/$token');
    return SharedCardModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get current user's shareable links.
  Future<Map<String, dynamic>> getMyShareableLinks({
    int limit = 20,
    int page = 1,
  }) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('$_basePath/mine', queryParameters: {
      'limit': limit,
      'page': page,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Revoke (delete) a shareable link.
  Future<Map<String, dynamic>> revokeShareableLink({required String id}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.delete('$_basePath/$id');
    return response.data as Map<String, dynamic>;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

final shareServiceProvider = Provider<ShareService>((ref) {
  return ShareService(ref);
});
