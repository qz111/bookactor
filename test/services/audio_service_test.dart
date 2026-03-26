import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bookactor/services/audio_service.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

// ──────────────────────────────────────────────────
// Minimal fake implementations of the audioplayers
// platform interfaces so no real platform channel is
// needed during unit tests.
// ──────────────────────────────────────────────────

class _FakeGlobalPlatform extends GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Future<void> emitGlobalError(String code, String message) async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
}

class _FakePlayerPlatform extends AudioplayersPlatformInterface {
  final Map<String, StreamController<AudioEvent>> _controllers = {};

  @override
  Future<void> create(String playerId) async {
    _controllers[playerId] = StreamController<AudioEvent>.broadcast();
  }

  @override
  Future<void> dispose(String playerId) async {
    await _controllers[playerId]?.close();
    _controllers.remove(playerId);
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _controllers[playerId]?.stream ?? const Stream.empty();

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> resume(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> seek(String playerId, Duration position) async {}

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    _controllers[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    _controllers[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setAudioContext(
    String playerId,
    AudioContext audioContext,
  ) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<int?> getDuration(String playerId) async => 0;

  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}
}

// ──────────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Install fake platform implementations before any AudioPlayer is created.
  GlobalAudioplayersPlatformInterface.instance = _FakeGlobalPlatform();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    AudioplayersPlatformInterface.instance = _FakePlayerPlatform();
  });

  test('AudioService can be instantiated and disposed without error', () async {
    final service = AudioService();
    expect(service, isNotNull);
    service.dispose();
  });

  test('AudioService play/pause/stop do not throw in test environment', () async {
    final service = AudioService();
    try {
      await service.load('/fake/path/line_000.mp3');
      await service.play();
      await service.pause();
      await service.stop();
    } catch (e) {
      // audioplayers platform channel not available in test environment — acceptable
      if (e.toString().contains('MissingPluginException')) {
        markTestSkipped('audioplayers platform channel not available in test environment');
        return;
      }
      rethrow;
    }
    service.dispose();
  });

  test('simulateComplete emits on onComplete stream', () async {
    final service = AudioService();
    final completer = Completer<void>();
    final sub = service.onComplete.listen((_) => completer.complete());

    service.simulateComplete();

    await completer.future.timeout(const Duration(seconds: 1));
    await sub.cancel();
    service.dispose();
  });

  test('seek delegates to audioplayers', () async {
    final mockPlayer = MockAudioPlayer();
    final controller = StreamController<void>.broadcast();
    when(() => mockPlayer.onPlayerComplete).thenAnswer((_) => controller.stream);
    when(() => mockPlayer.seek(any())).thenAnswer((_) async {});
    when(() => mockPlayer.dispose()).thenAnswer((_) async {});
    final service = AudioService.withPlayer(mockPlayer);
    await service.seek(const Duration(seconds: 5));
    verify(() => mockPlayer.seek(const Duration(seconds: 5))).called(1);
    await controller.close();
    service.dispose();
  });

  test('positionStream exposes player onPositionChanged', () {
    final mockPlayer = MockAudioPlayer();
    final completeController = StreamController<void>.broadcast();
    final positionController = StreamController<Duration>.broadcast();
    when(() => mockPlayer.onPlayerComplete)
        .thenAnswer((_) => completeController.stream);
    when(() => mockPlayer.onPositionChanged)
        .thenAnswer((_) => positionController.stream);
    final service = AudioService.withPlayer(mockPlayer);
    expect(service.positionStream,
        emitsInOrder([const Duration(seconds: 1)]));
    positionController.add(const Duration(seconds: 1));
    positionController.close();
    completeController.close();
  });
}
