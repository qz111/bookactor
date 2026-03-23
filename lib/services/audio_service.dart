import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final AudioPlayer _player;
  final StreamController<void> _onCompleteController =
      StreamController<void>.broadcast();

  AudioService() : _player = AudioPlayer() {
    _player.onPlayerComplete.listen((_) {
      _onCompleteController.add(null);
    });
  }

  Stream<void> get onComplete => _onCompleteController.stream;

  Future<void> load(String filePath) async {
    await _player.setSourceDeviceFile(filePath);
  }

  Future<void> play() => _player.resume();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();

  /// Test-only: simulate playback completion without needing a real audio file.
  void simulateComplete() => _onCompleteController.add(null);

  void dispose() {
    _onCompleteController.close();
    _player.dispose();
  }
}
