import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookactor/services/api_service.dart';
import 'package:bookactor/models/processing_mode.dart';

void main() {
  const baseUrl = 'http://localhost:8000';

  ApiService makeService(MockClient client) => ApiService(
        baseUrl: baseUrl,
        openAiKey: 'test-openai-key',
        googleKey: 'test-google-key',
        client: client,
      );

  group('analyzePages', () {
    test('sends images as multipart and returns pages list', () async {
      final fakePages = [
        {'page': 1, 'text': 'Once upon a time'}
      ];
      final client = MockClient((request) async {
        expect(request.url.path, '/analyze');
        expect(request.method, 'POST');
        final bodyStr = String.fromCharCodes(request.bodyBytes);
        expect(bodyStr, contains('processing_mode'));
        expect(bodyStr, contains('text_heavy'));
        expect(bodyStr, contains('openai_api_key'));
        expect(bodyStr, contains('test-openai-key'));
        expect(bodyStr, contains('google_api_key'));
        expect(bodyStr, contains('test-google-key'));
        return http.Response(
          jsonEncode({'pages': fakePages}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = makeService(client);
      final result = await service.analyzePages(
        imageBytesList: [Uint8List.fromList([0, 1, 2])],
        vlmProvider: 'gemini',
        processingMode: ProcessingMode.textHeavy,
      );
      expect(result, fakePages);
    });

    test('throws ApiException on non-200 response', () async {
      final client = MockClient((_) async => http.Response('error', 422));
      final service = makeService(client);
      await expectLater(
        () => service.analyzePages(
          imageBytesList: [],
          vlmProvider: 'gemini',
          processingMode: ProcessingMode.textHeavy,
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('generateScript', () {
    test('posts vlm_output + language + llm_provider + keys and returns script', () async {
      final fakeScript = {
        'characters': [{'name': 'Narrator', 'voice': 'alloy'}],
        'lines': <dynamic>[],
      };
      final client = MockClient((request) async {
        expect(request.url.path, '/script');
        final body = jsonDecode(request.body) as Map;
        expect(body['language'], 'zh');
        expect(body['openai_api_key'], 'test-openai-key');
        expect(body['google_api_key'], 'test-google-key');
        return http.Response(
          jsonEncode({'script': fakeScript}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = makeService(client);
      final result = await service.generateScript(
        vlmOutput: [{'page': 1, 'text': 'Hello'}],
        language: 'zh',
        llmProvider: 'gpt4o',
      );
      expect(result['characters'], isNotEmpty);
    });

    test('throws ApiException on error', () async {
      final client = MockClient((_) async => http.Response('bad', 500));
      final service = makeService(client);
      await expectLater(
        () => service.generateScript(vlmOutput: [], language: 'en', llmProvider: 'gpt4o'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('generateAudio', () {
    test('posts chunks with voice_map and returns results with duration_ms', () async {
      final fakeResults = [
        {'index': 0, 'status': 'ready', 'audio_b64': base64Encode([1, 2, 3]), 'duration_ms': 8400}
      ];
      final client = MockClient((request) async {
        expect(request.url.path, '/tts');
        final body = jsonDecode(request.body) as Map;
        expect(body['chunks'], isNotEmpty);
        expect(body['chunks'][0]['voice_map'], isA<Map>());
        expect(body.containsKey('lines'), false);
        expect(body['openai_api_key'], 'test-openai-key');
        return http.Response(
          jsonEncode(fakeResults),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = makeService(client);
      final result = await service.generateAudio(chunks: [
        {'index': 0, 'text': 'Narrator: Hi.', 'voice_map': {'Narrator': 'Aoede'}}
      ]);
      expect(result.first['status'], 'ready');
      expect(result.first['duration_ms'], 8400);
    });
  });
}
