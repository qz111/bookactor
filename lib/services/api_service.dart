import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/processing_mode.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  final String baseUrl;
  final String openAiKey;
  final String googleKey;
  final String qwenKey;
  final http.Client client;

  ApiService({
    required this.baseUrl,
    required this.openAiKey,
    required this.googleKey,
    this.qwenKey = '',
    http.Client? client,
  }) : client = client ?? http.Client();

  Future<List<Map<String, dynamic>>> analyzePages({
    required List<Uint8List> imageBytesList,
    required String vlmProvider,
    required ProcessingMode processingMode,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/analyze'))
      ..fields['vlm_provider'] = vlmProvider
      ..fields['processing_mode'] = processingMode.toApiValue()
      ..fields['openai_api_key'] = openAiKey
      ..fields['google_api_key'] = googleKey;
    for (int i = 0; i < imageBytesList.length; i++) {
      request.files.add(http.MultipartFile.fromBytes(
        'images',
        imageBytesList[i],
        filename: 'page_${i + 1}.jpg',
      ));
    }
    final streamed = await client.send(request);
    final response = await http.Response.fromStream(streamed);
    _checkStatus(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['pages'] as List);
  }

  Future<Map<String, dynamic>> generateScript({
    required List<Map<String, dynamic>> vlmOutput,
    required String language,
    required String llmProvider,
    String ttsProvider = 'openai',
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/script'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'vlm_output': vlmOutput,
        'language': language,
        'llm_provider': llmProvider,
        'tts_provider': ttsProvider,
        'openai_api_key': openAiKey,
        'google_api_key': googleKey,
      }),
    );
    _checkStatus(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['script'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> generateAudio({
    required List<Map<String, dynamic>> chunks,
    String ttsProvider = 'openai',
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/tts'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'chunks': chunks,
        'tts_provider': ttsProvider,
        'openai_api_key': openAiKey,
        'google_api_key': googleKey,
        'qwen_api_key': qwenKey,
      }),
    );
    _checkStatus(response);
    return List<Map<String, dynamic>>.from(jsonDecode(response.body) as List);
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
  }
}
