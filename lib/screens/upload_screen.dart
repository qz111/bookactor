import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../db/database.dart';
import '../mock/mock_data.dart';
import '../models/audio_version.dart';
import '../models/book.dart';
import '../screens/loading_screen.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  String? _selectedFileName;
  String? _selectedFilePath;
  bool _isGenerating = false;
  String _language = 'en';
  String _vlmProvider = 'gemini';
  String _llmProvider = 'gpt4o';

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null) {
      setState(() {
        _selectedFileName = result.files.single.name;
        _selectedFilePath = result.files.single.path;
      });
    }
  }

  Future<void> _generate() async {
    if (_selectedFilePath == null) return;
    setState(() => _isGenerating = true);
    try {
      final fileBytes = await File(_selectedFilePath!).readAsBytes();
      final bookId = sha256.convert(fileBytes).toString();

      // Persist the book row (vlm_output populated after /analyze in LoadingScreen)
      await AppDatabase.instance.insertBook(Book(
        bookId: bookId,
        title: _selectedFileName ?? 'Untitled',
        coverPath: null,
        pagesDir: _selectedFilePath!,
        vlmOutput: '',
        vlmProvider: _vlmProvider,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ));

      // Insert generating audio_version placeholder
      final versionId = '${bookId}_$_language';
      await AppDatabase.instance.insertAudioVersion(AudioVersion(
        versionId: versionId,
        bookId: bookId,
        language: _language,
        llmProvider: _llmProvider,
        scriptJson: '{}',
        audioDir: '',
        status: 'generating',
        lastGeneratedLine: 0,
        lastPlayedLine: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ));

      if (!mounted) return;
      context.push(
        '/loading',
        extra: LoadingParams(
          bookId: bookId,
          versionId: versionId,
          filePath: _selectedFilePath!,
          language: _language,
          vlmProvider: _vlmProvider,
          llmProvider: _llmProvider,
          isNewBook: true,
          lastGeneratedLine: -1,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Book')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          GestureDetector(
            onTap: _pickFile,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.3),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.upload_file, size: 40),
                    const SizedBox(height: 8),
                    Text(_selectedFileName ?? 'Tap to select PDF or images'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _language,
            decoration: const InputDecoration(
                labelText: 'Audio Language', border: OutlineInputBorder()),
            items: supportedLanguages
                .map((l) => DropdownMenuItem(
                    value: l['code'], child: Text(l['name']!)))
                .toList(),
            onChanged: (v) => setState(() => _language = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _vlmProvider,
            decoration: const InputDecoration(
                labelText: 'Vision Model (VLM)', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'gemini', child: Text('Gemini Vision')),
              DropdownMenuItem(value: 'gpt4o', child: Text('GPT-4o Vision')),
            ],
            onChanged: (v) => setState(() => _vlmProvider = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _llmProvider,
            decoration: const InputDecoration(
                labelText: 'Language Model (LLM)',
                border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'gpt4o', child: Text('GPT-4o')),
              DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
            ],
            onChanged: (v) => setState(() => _llmProvider = v!),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: (_selectedFilePath == null || _isGenerating) ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate Audiobook'),
          ),
        ],
      ),
    );
  }
}
