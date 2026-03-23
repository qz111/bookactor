import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  final String baseUrl;
  final http.Client client;

  ApiService({required this.baseUrl, http.Client? client})
      : client = client ?? http.Client();

  Future<List<Map<String, dynamic>>> analyzePages({
    required List<Uint8List> imageBytesList,
    required String vlmProvider,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/analyze'))
      ..fields['vlm_provider'] = vlmProvider;
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
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/script'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'vlm_output': vlmOutput,
        'language': language,
        'llm_provider': llmProvider,
      }),
    );
    _checkStatus(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data['script'] as Map);
  }

  Future<List<Map<String, dynamic>>> generateAudio({
    required List<Map<String, dynamic>> lines,
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/tts'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'lines': lines}),
    );
    _checkStatus(response);
    final data = jsonDecode(response.body) as List;
    return List<Map<String, dynamic>>.from(data);
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }
}
