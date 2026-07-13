// test/features/voice_memos/voice_memo_test.dart
// P7.4b — Voice memo tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/voice_memos/providers/voice_memo_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P7.4b — Voice memo', () {
    test('default state is not recording', () {
      final controller = VoiceMemoController();
      expect(controller.state.isRecording, isFalse);
      controller.dispose();
    });

    test('startRecording sets isRecording=true', () async {
      final controller = VoiceMemoController();
      await controller.startRecording();
      expect(controller.state.isRecording, isTrue);
      controller.dispose();
    });

    test('pauseRecording sets isPaused=true', () async {
      final controller = VoiceMemoController();
      await controller.startRecording();
      await controller.pauseRecording();
      expect(controller.state.isPaused, isTrue);
      controller.dispose();
    });

    test('stopRecording resets state', () async {
      final controller = VoiceMemoController();
      await controller.startRecording();
      await controller.stopRecording();
      expect(controller.state.isRecording, isFalse);
      controller.dispose();
    });

    test('cancelRecording resets state', () async {
      final controller = VoiceMemoController();
      await controller.startRecording();
      await controller.cancelRecording();
      expect(controller.state.isRecording, isFalse);
      controller.dispose();
    });
  });
}
