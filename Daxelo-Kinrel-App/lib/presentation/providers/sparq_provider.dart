// lib/presentation/providers/sparq_provider.dart
//
// DAXELO KINREL — Sparq Provider
//
// Manages Sparq (ephemeral story) state:
//   • fetchFeed → load feed, sort: hasUnseen first, then by createdAt
//   • fetchMySparqs
//   • createSparq → show loading, upload, add to mySparqs on success
//   • deleteSparq
//   • markViewed → update viewed flag in feed cache
//   • refreshFeed → called when app resumes

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/sparq_repository.dart';
import '../../data/models/sparq_model.dart';

// ═══════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════

class SparqState {
  const SparqState({
    this.feed = const [],
    this.mySparqs = const [],
    this.isLoading = false,
    this.isCreating = false,
    this.error,
  });

  final List<UserSparqGroup> feed;
  final List<SparqModel> mySparqs;
  final bool isLoading;
  final bool isCreating;
  final String? error;

  SparqState copyWith({
    List<UserSparqGroup>? feed,
    List<SparqModel>? mySparqs,
    bool? isLoading,
    bool? isCreating,
    String? error,
    bool clearError = false,
  }) {
    return SparqState(
      feed: feed ?? this.feed,
      mySparqs: mySparqs ?? this.mySparqs,
      isLoading: isLoading ?? this.isLoading,
      isCreating: isCreating ?? this.isCreating,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NOTIFIER
// ═══════════════════════════════════════════════════════════════════════

class SparqNotifier extends StateNotifier<SparqState> {
  SparqNotifier(this._ref) : super(const SparqState());

  final Ref _ref;
  SparqRepository get _repo => _ref.read(sparqRepositoryProvider);

  /// Fetch the Sparq feed. Sorts: hasUnseen groups first, then by
  /// the most recent createdAt within each group.
  Future<void> fetchFeed() async {
    state = super.state.copyWith(isLoading: true, clearError: true);
    try {
      final feed = await _repo.getSparqFeed();
      // Sort: unseen first, then by most recent sparq createdAt
      final sorted = List<UserSparqGroup>.from(feed)..sort((a, b) {
        // Unseen groups come first
        if (a.hasUnseen != b.hasUnseen) {
          return a.hasUnseen ? -1 : 1;
        }
        // Then by most recent sparq createdAt (newest first)
        final aTime = a.sparqs.isNotEmpty ? a.sparqs.first.createdAt : DateTime.now();
        final bTime = b.sparqs.isNotEmpty ? b.sparqs.first.createdAt : DateTime.now();
        return bTime.compareTo(aTime);
      });
      state = super.state.copyWith(feed: sorted, isLoading: false);
    } catch (e) {
      debugPrint('⚠️ fetchFeed error: $e');
      state = super.state.copyWith(
        isLoading: false,
        error: 'Failed to load Sparq feed.',
      );
    }
  }

  /// Fetch the current user's own Sparqs.
  Future<void> fetchMySparqs() async {
    try {
      final mySparqs = await _repo.getMySparqs();
      state = super.state.copyWith(mySparqs: mySparqs);
    } catch (e) {
      debugPrint('⚠️ fetchMySparqs error: $e');
      state = super.state.copyWith(
        error: 'Failed to load your Sparqs.',
      );
    }
  }

  /// Create a new Sparq. Shows loading state, uploads, and adds to
  /// mySparqs on success.
  Future<SparqModel?> createSparq({
    required String type,
    required String audience,
    dynamic mediaFile,
    String? text,
    String? bgColor,
  }) async {
    state = super.state.copyWith(isCreating: true, clearError: true);
    try {
      final sparq = await _repo.createSparq(
        type: type,
        audience: audience,
        mediaFile: mediaFile,
        text: text,
        bgColor: bgColor,
      );
      // Add to mySparqs list
      final updatedMySparqs = [sparq, ...super.state.mySparqs];
      state = super.state.copyWith(
        mySparqs: updatedMySparqs,
        isCreating: false,
      );
      // Refresh feed to include the new sparq
      unawaited(fetchFeed());
      return sparq;
    } catch (e) {
      debugPrint('⚠️ createSparq error: $e');
      state = super.state.copyWith(
        isCreating: false,
        error: 'Failed to create Sparq. Please try again.',
      );
      return null;
    }
  }

  /// Delete a Sparq by ID.
  Future<void> deleteSparq(String sparqId) async {
    try {
      await _repo.deleteSparq(sparqId);
      // Remove from mySparqs
      final updatedMySparqs =
          super.state.mySparqs.where((s) => s.id != sparqId).toList();
      // Remove from feed
      final updatedFeed = super.state.feed.map((group) {
        final updatedSparqs =
            group.sparqs.where((s) => s.id != sparqId).toList();
        if (updatedSparqs.isEmpty) return null;
        return UserSparqGroup(
          userId: group.userId,
          user: group.user,
          sparqs: updatedSparqs,
          hasUnseen: updatedSparqs.any((s) => !s.viewed),
          totalCount: group.totalCount,
        );
      }).whereType<UserSparqGroup>().toList();
      state = super.state.copyWith(
        mySparqs: updatedMySparqs,
        feed: updatedFeed,
      );
    } catch (e) {
      debugPrint('⚠️ deleteSparq error: $e');
      state = super.state.copyWith(
        error: 'Failed to delete Sparq.',
      );
    }
  }

  /// Mark a Sparq as viewed. Updates the viewed flag in the feed cache.
  Future<void> markViewed(String sparqId) async {
    // Optimistic update
    final updatedFeed = super.state.feed.map((group) {
      final updatedSparqs = group.sparqs.map((s) {
        if (s.id == sparqId) {
          return SparqModel(
            id: s.id,
            userId: s.userId,
            type: s.type,
            mediaUrl: s.mediaUrl,
            thumbnailUrl: s.thumbnailUrl,
            text: s.text,
            bgColor: s.bgColor,
            duration: s.duration,
            audience: s.audience,
            expiresAt: s.expiresAt,
            createdAt: s.createdAt,
            viewCount: s.viewCount,
            viewed: true,
          );
        }
        return s;
      }).toList();
      final hasUnseen = updatedSparqs.any((s) => !s.viewed);
      return UserSparqGroup(
        userId: group.userId,
        user: group.user,
        sparqs: updatedSparqs,
        hasUnseen: hasUnseen,
        totalCount: group.totalCount,
      );
    }).toList();
    state = super.state.copyWith(feed: updatedFeed);

    // Fire and forget API call
    try {
      await _repo.markViewed(sparqId);
    } catch (e) {
      debugPrint('⚠️ markViewed error: $e');
    }
  }

  /// Refresh the feed (called when app resumes).
  Future<void> refreshFeed() async {
    await fetchFeed();
  }
}

// unawaited is provided by dart:async — no custom definition needed.

// ═══════════════════════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Main Sparq state notifier provider.
final sparqProvider =
    StateNotifierProvider<SparqNotifier, SparqState>((ref) {
  return SparqNotifier(ref);
});
