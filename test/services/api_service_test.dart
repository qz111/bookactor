import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookactor/services/api_service.dart';

void main() {
  const baseUrl = 'http://localhost:8000';

  group('analyzePages', () {
    test('sends images as multipart and returns pages list', () async {
      final fakePages = [
        {'page': 1, 'text': 'Once upon a time'}
      ];
      final client = MockClient((request) async {
        expect(request.url.path, '/analyze');
        expect(request.method, 'POST');
        return http.Response(
          jsonEncode({'pages': fakePages}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = ApiService(baseUrl: baseUrl, client: client);
      final result = await service.analyzePages(
        imageBytesList: [Uint8List.fromList([0, 1, 2])],
        vlmProvider: 'gemini',
      );
      expect(result, fakePages);
    });

    test('throws ApiException on non-200 response', () async {
      final client = MockClient((_) async => http.Response('error', 422));
      final service = ApiService(baseUrl: baseUrl, client: client);
      await expectLater(
        () => service.analyzePages(imageBytesList: [], vlmProvider: 'gemini'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('generateScript', () {
    test('posts vlm_output + language + llm_provider and returns script', () async {
      final fakeScript = {
        'characters': [{'name': 'Narrator', 'voice': 'alloy'}],
        'lines': <dynamic>[],
      };
      final client = MockClient((request) async {
        expect(request.url.path, '/script');
        final body = jsonDecode(request.body) as Map;
        expect(body['language'], 'zh');
        return http.Response(
          jsonEncode({'script': fakeScript}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = ApiService(baseUrl: baseUrl, client: client);
      final result = await service.generateScript(
        vlmOutput: [{'page': 1, 'text': 'Hello'}],
        language: 'zh',
        llmProvider: 'gpt4o',
      );
      expect(result['characters'], isNotEmpty);
    });

    test('throws ApiException on error', () async {
      final client = MockClient((_) async => http.Response('bad', 500));
      final service = ApiService(baseUrl: baseUrl, client: client);
      await expectLater(
        () => service.generateScript(vlmOutput: [], language: 'en', llmProvider: 'gpt4o'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('generateAudio', () {
    test('posts lines and returns audio results', () async {
      final fakeResults = [
        {'index': 0, 'status': 'ready', 'audio_b64': base64Encode([1, 2, 3])}
      ];
      final client = MockClient((request) async {
        expect(request.url.path, '/tts');
        final body = jsonDecode(request.body) as Map;
        expect(body['lines'], isNotEmpty);
        return http.Response(
          jsonEncode(fakeResults),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = ApiService(baseUrl: baseUrl, client: client);
      final result = await service.generateAudio(lines: [
        {'index': 0, 'text': 'Hi', 'voice': 'alloy'}
      ]);
      expect(result.first['status'], 'ready');
    });
  });
}
