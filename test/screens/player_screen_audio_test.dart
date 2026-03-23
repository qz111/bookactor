import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:bookactor/screens/player_screen.dart';
import 'package:bookactor/services/audio_service.dart';

// ──────────────────────────────────────────────────
// Minimal fake platform implementations so AudioPlayer()
// constructor does not throw MissingPluginException.
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
  Future<void> setSourceUrl(String playerId, String url,
      {bool? isLocal, String? mimeType}) async {}
  @override
  Future<void> setSourceBytes(String playerId, Uint8List bytes,
      {String? mimeType}) async {}
  @override
  Future<void> setAudioContext(
      String playerId, AudioContext audioContext) async {}
  @override
  Future<void> setPlayerMode(
      String playerId, PlayerMode playerMode) async {}
  @override
  Future<int?> getDuration(String playerId) async => 0;
  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;
  @override
  Future<void> emitLog(String playerId, String message) async {}
  @override
  Future<void> emitError(
      String playerId, String code, String message) async {}
}

// ──────────────────────────────────────────────────
// Fake AudioService that records calls without real audio
// ──────────────────────────────────────────────────

class _FakeAudioService extends AudioService {
  bool loadCalled = false;
  bool playCalled = false;
  String? lastLoadedPath;

  _FakeAudioService();

  @override
  Future<void> load(String filePath) async {
    loadCalled = true;
    lastLoadedPath = filePath;
  }

  @override
  Future<void> play() async {
    playCalled = true;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {
    // do nothing — avoid platform calls
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Install fake platform implementations before any AudioPlayer is created.
  GlobalAudioplayersPlatformInterface.instance = _FakeGlobalPlatform();

  setUp(() {
    AudioplayersPlatformInterface.instance = _FakePlayerPlatform();
  });

  testWidgets(
      'PlayerScreen uses AudioService for mock_book_001_en (simulateComplete auto-advance)',
      (tester) async {
    final fakeAudio = _FakeAudioService();

    final router = GoRouter(
      initialLocation: '/player/mock_book_001_en',
      routes: [
        GoRoute(
          path: '/player/:versionId',
          builder: (context, state) => PlayerScreen(
            versionId: state.pathParameters['versionId']!,
            audioService: fakeAudio,
          ),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: router),
    ));

    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Mock data should be loaded; AudioService.load should have been called
    expect(fakeAudio.loadCalled, isTrue);
  });
}
