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

  /// Test-only constructor: inject a mock AudioPlayer.
  AudioService.withPlayer(this._player) {
    _player.onPlayerComplete.listen((_) {
      _onCompleteController.add(null);
    });
  }

  Stream<void> get onComplete => _onCompleteController.stream;

  Stream<Duration> get positionStream => _player.onPositionChanged;

  Future<void> load(String filePath) async {
    await _player.setSourceDeviceFile(filePath);
  }

  Future<void> play() => _player.resume();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position) => _player.seek(position);

  /// Test-only: simulate playback completion.
  void simulateComplete() => _onCompleteController.add(null);

  void dispose() {
    _onCompleteController.close();
    _player.dispose();
  }
}
