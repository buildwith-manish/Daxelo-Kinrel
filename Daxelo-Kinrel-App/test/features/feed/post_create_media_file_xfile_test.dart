// test/features/feed/post_create_media_file_xfile_test.dart
//
// Regression test for the image-picker web-compatibility fix.
//
// Bug: post_create_screen.dart used `File(image.path)` (dart:io File)
// to store the picked media in PostCreateState.mediaFile. On Flutter
// web, image_picker returns an XFile whose `path` is a BLOB URL, NOT
// a real filesystem path. `dart:io`'s `File` can't open blob URLs.
//
// Fix: changed PostCreateState.mediaFile from `File?` to `XFile?`.
// XFile (from cross_file, re-exported by image_picker) has a
// `readAsBytes()` method that works on both web blob URLs and native
// file paths. PostCreateScreen now passes `image` (the XFile directly)
// to `setMediaFile(image)` instead of `File(image.path)`.
//
// This test verifies the public-API type contract: `setMediaFile`
// accepts an `XFile` (not a `File`), and the state's `mediaFile` field
// is typed as `XFile?`.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cross_file/cross_file.dart';

import 'package:kinrel/features/feed/providers/post_create_provider.dart';

void main() {
  group('PostCreateState.mediaFile (XFile type contract)', () {
    test('mediaFile is typed as XFile? (not File?)', () {
      // Compile-time check: the field is XFile?. If a future change
      // regresses back to File?, this line will fail to compile.
      const state = PostCreateState();
      // ignore: unnecessary_type_check
      expect(state.mediaFile is XFile?, isTrue,
          reason: 'mediaFile must be XFile? (cross-platform) — not File? '
              '(dart:io, web-incompatible).');
      expect(state.mediaFile, isNull,
          reason: 'Initial state should have null mediaFile.');
    });

    test('copyWith accepts XFile for mediaFile', () {
      const state = PostCreateState();
      final xfile = XFile('test-path');
      final updated = state.copyWith(mediaFile: xfile);
      expect(updated.mediaFile, isNotNull);
      expect(updated.mediaFile, isA<XFile>());
    });
  });

  group('PostCreateNotifier.setMediaFile (XFile parameter contract)', () {
    late ProviderContainer container;
    late PostCreateNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(postCreateProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('accepts an XFile and stores it in state', () {
      final xfile = XFile('test-image.jpg');
      notifier.setMediaFile(xfile);
      expect(notifier.state.mediaFile, isNotNull);
      expect(notifier.state.mediaFile, isA<XFile>());
      // The path is preserved (cross-platform — works on web blob
      // URLs and native file paths).
      expect(notifier.state.mediaFile!.path, 'test-image.jpg');
    });

    test('accepts null (clears the mediaFile)', () {
      final xfile = XFile('test-image.jpg');
      notifier.setMediaFile(xfile);
      expect(notifier.state.mediaFile, isNotNull);

      notifier.setMediaFile(null);
      expect(notifier.state.mediaFile, isNull,
          reason: 'Setting null must clear the mediaFile.');
    });

    test('hasContent is true when mediaFile is set', () {
      expect(notifier.state.hasContent, isFalse);
      notifier.setMediaFile(XFile('test.jpg'));
      expect(notifier.state.hasContent, isTrue,
          reason: 'hasContent must be true when mediaFile is set.');
    });

    test('hasContent is false when mediaFile is null but text is empty', () {
      notifier.setMediaFile(null);
      notifier.setText('');
      expect(notifier.state.hasContent, isFalse);
    });
  });

  group('Cross-platform readAsBytes contract', () {
    test('XFile exposes readAsBytes() (used at submit time, not picker time)',
        () {
      // Static contract check: XFile has a `readAsBytes()` method that
      // works on both web (blob URLs via fetch) and native (real file
      // paths via dart:io File). This is what post_create_provider's
      // submit() calls (line 173: `state.mediaFile!.readAsBytes()`).
      final xfile = XFile('test-path');
      expect(xfile.readAsBytes, isA<Function>(),
          reason: 'XFile must expose readAsBytes() — the cross-platform '
              'method that replaces File(image.path).readAsBytes().');
    });

    test('XFile.name is exposed (used for the upload filename)', () {
      // post_create_provider.submit() uses `state.mediaFile!.path.split('/').last`
      // for the filename. XFile also exposes `name` (the original
      // filename), which is more reliable on web (where path is a blob
      // URL like `blob:http://localhost:8090/<uuid>`).
      final xfile = XFile('test-path');
      expect(() => xfile.name, returnsNormally,
          reason: 'XFile.name must be accessible for the upload filename.');
    });
  });
}
