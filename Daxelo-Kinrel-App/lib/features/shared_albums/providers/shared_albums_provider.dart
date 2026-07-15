// lib/features/shared_albums/providers/shared_albums_provider.dart
//
// P9.2f — Event-scoped shared albums.
//
// Albums are scoped to a single event (a festival, a wedding, a
// memorial). This provider keeps an in-memory list per event and is
// keyed by `eventId`. In production this would back onto Supabase
// storage; here it is a minimal, deterministic store so it can be
// unit-tested without assets.
//
// Constitution / Copy-Audit: no "most-liked photo" surfacing, no view
// counts shown to contributors, no engagement leaderboards. Photos are
// listed neutrally in upload order.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class SharedAlbumPhoto {
  const SharedAlbumPhoto({
    required this.id,
    required this.uploaderId,
    required this.uploadedAt,
    this.caption,
  });

  final String id;
  final String uploaderId;
  final DateTime uploadedAt;
  final String? caption;
}

@immutable
class SharedAlbum {
  const SharedAlbum({
    required this.id,
    required this.eventId,
    required this.title,
    required this.createdAt,
    this.photos = const [],
  });

  final String id;
  final String eventId;
  final String title;
  final DateTime createdAt;
  final List<SharedAlbumPhoto> photos;

  int get photoCount => photos.length;

  SharedAlbum copyWith({
    String? id,
    String? eventId,
    String? title,
    DateTime? createdAt,
    List<SharedAlbumPhoto>? photos,
  }) {
    return SharedAlbum(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      photos: photos ?? this.photos,
    );
  }
}

@immutable
class SharedAlbumsState {
  const SharedAlbumsState({
    this.albums = const [],
    this.isLoading = false,
    this.error,
  });

  final List<SharedAlbum> albums;
  final bool isLoading;
  final String? error;

  SharedAlbumsState copyWith({
    List<SharedAlbum>? albums,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return SharedAlbumsState(
      albums: albums ?? this.albums,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SharedAlbumsNotifier extends StateNotifier<SharedAlbumsState> {
  SharedAlbumsNotifier(this.eventId) : super(const SharedAlbumsState());

  final String eventId;
  int _albumCounter = 0;
  int _photoCounter = 0;

  String _newAlbumId() => 'album-$eventId-${_albumCounter++}';
  String _newPhotoId() => 'photo-$eventId-${_photoCounter++}';

  void load(List<SharedAlbum> seed) {
    final mine = seed.where((a) => a.eventId == eventId).toList();
    state = SharedAlbumsState(albums: mine);
  }

  /// Creates an album for this event.
  void createAlbum(String title) {
    final t = title.trim();
    if (t.isEmpty) {
      state = state.copyWith(error: 'Album needs a title.');
      return;
    }
    final album = SharedAlbum(
      id: _newAlbumId(),
      eventId: eventId,
      title: t,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(albums: [...state.albums, album], clearError: true);
  }

  /// Adds a photo reference to an album. No view-count, no like count.
  void addPhoto(String albumId, {required String uploaderId, String? caption}) {
    state = state.copyWith(
      albums: [
        for (final a in state.albums)
          if (a.id == albumId)
            a.copyWith(photos: [
              ...a.photos,
              SharedAlbumPhoto(
                id: _newPhotoId(),
                uploaderId: uploaderId,
                uploadedAt: DateTime.now(),
                caption: caption?.trim().isEmpty == true ? null : caption?.trim(),
              ),
            ])
          else
            a,
      ],
    );
  }

  void removePhoto(String albumId, String photoId) {
    state = state.copyWith(
      albums: [
        for (final a in state.albums)
          if (a.id == albumId)
            a.copyWith(photos: a.photos.where((p) => p.id != photoId).toList())
          else
            a,
      ],
    );
  }

  void removeAlbum(String albumId) {
    state = state.copyWith(
      albums: state.albums.where((a) => a.id != albumId).toList(),
    );
  }

  void clearError() => state = state.copyWith(clearError: true);
}

/// Keyed by eventId so each event's album list is independent.
final sharedAlbumsProvider = StateNotifierProvider.autoDispose
    .family<SharedAlbumsNotifier, SharedAlbumsState, String>(
  (ref, eventId) => SharedAlbumsNotifier(eventId),
);
