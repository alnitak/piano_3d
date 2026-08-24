import 'package:flutter_test/flutter_test.dart';
import 'package:piano_3d/audio/audio_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AudioController initial state and buffer dimensions', () {
    final controller = AudioController.instance;

    expect(controller.fftData.length, equals(166));
    expect(controller.texture2dData.length, equals(256 * 512));
    expect(controller.isInitialized, isFalse);
    expect(controller.hasActiveAudio, isFalse);
  });
}
