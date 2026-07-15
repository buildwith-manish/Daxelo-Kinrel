// test/features/shared_albums/shared_albums_provider_test.dart
//
// P9.2f — Event-scoped shared album tests.
// Verifies no view-count / like-count surface and per-event isolation.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/shared_albums/providers/shared_albums_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P9.2f — SharedAlbumsNotifier (per event)', () {
    test('two events are isolated', () {
      final a = SharedAlbumsNotifier('event-a');
      final b = SharedAlbumsNotifier('event-b');
      a.createAlbum('Wedding');
      expect(a.state.albums, hasLength(1));
      expect(b.state.albums, isEmpty);
      a.dispose();
      b.dispose();
    });

    test('createAlbum rejects empty title', () {
      final n = SharedAlbumsNotifier('event-x');
      n.createAlbum('   ');
      expect(n.state.albums, isEmpty);
      expect(n.state.error, 'Album needs a title.');
      n.dispose();
    });

    test('addPhoto appends without any view/like count', () {
      final n = SharedAlbumsNotifier('event-x');
      n.createAlbum('Reunion');
      final albumId = n.state.albums.single.id;
      n.addPhoto(albumId, uploaderId: 'u1', caption: '  ');
      expect(n.state.albums.single.photos, hasLength(1));
      expect(n.state.albums.single.photos.single.caption, isNull);
      // photoCount is the only count surfaced; there is no likes/views.
      expect(n.state.albums.single.photoCount, 1);
      n.dispose();
    });

    test('removePhoto drops by id', () {
      final n = SharedAlbumsNotifier('event-x');
      n.createAlbum('Reunion');
      final albumId = n.state.albums.single.id;
      n.addPhoto(albumId, uploaderId: 'u1');
      n.addPhoto(albumId, uploaderId: 'u2');
      final first = n.state.albums.single.photos.first.id;
      n.removePhoto(albumId, first);
      expect(n.state.albums.single.photos, hasLength(1));
      n.dispose();
    });

    test('removeAlbum drops by id', () {
      final n = SharedAlbumsNotifier('event-x');
      n.createAlbum('a');
      n.createAlbum('b');
      n.removeAlbum(n.state.albums.first.id);
      expect(n.state.albums, hasLength(1));
      n.dispose();
    });

    test('load filters to this event only', () {
      final n = SharedAlbumsNotifier('event-x');
      n.load([
        SharedAlbum(
          id: '1',
          eventId: 'event-x',
          title: 'mine',
          createdAt: DateTime.now(),
        ),
        SharedAlbum(
          id: '2',
          eventId: 'other',
          title: 'not mine',
          createdAt: DateTime.now(),
        ),
      ]);
      expect(n.state.albums, hasLength(1));
      expect(n.state.albums.single.eventId, 'event-x');
      n.dispose();
    });
  });
}
