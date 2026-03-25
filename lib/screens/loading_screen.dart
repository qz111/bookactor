import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/settings_provider.dart';
import '../models/audio_version.dart';
import '../models/processing_mode.dart';
import '../services/api_service.dart';
import '../services/pdf_service.dart';

/// Parameters passed to LoadingScreen via GoRouter's extra field.
class LoadingParams {
  final String bookId;
  final String versionId;
  final String filePath;
  final String language;
  final String vlmProvider;
  final String llmProvider;
  final String ttsProvider;
  final ProcessingMode processingMode;
  final bool isNewBook;
  final int lastGeneratedLine;
  /// Optional override for the audio output directory (useful in tests).
  final String? audioDirOverride;
  /// Optional list of image paths for multi-image mode.
  /// When non-null and non-empty, these files are read in order instead of [filePath].
  final List<String>? imageFilePaths;

  const LoadingParams({
    required this.bookId,
    required this.versionId,
    required this.filePath,
    required this.language,
    required this.vlmProvider,
    required this.llmProvider,
    required this.ttsProvider,
    required this.processingMode,
    required this.isNewBook,
    required this.lastGeneratedLine,
    this.audioDirOverride,
    this.imageFilePaths,
  });
}

class LoadingScreen extends ConsumerStatefulWidget {
  final String bookId;
  final String language;
  final LoadingParams? params;
  final ApiService? apiService;

  const LoadingScreen({
    super.key,
    this.bookId = '',
    this.language = 'en',
    this.params,
    this.apiService,
  });

  @override
  ConsumerState<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends ConsumerState<LoadingScreen> {
  int _step = 0; // 0=not started, 1=reading done, 2=scripting done, 3=done
  bool _hasError = false;

  static const _steps = [
    (icon: '📖', label: 'Reading pages...'),
    (icon: '✍️', label: 'Writing script...'),
    (icon: '🎙️', label: 'Recording voices...'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.params != null) {
      _runLivePipeline();
    } else {
      _runMockPipeline();
    }
  }

  Future<void> _runMockPipeline() async {
    for (int i = 0; i < _steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() => _step = i + 1);
    }
    if (!mounted) return;
    // Phase 2: always navigates to mock English version
    context.go('/player/mock_book_001_en', extra: true);
  }

  Future<void> _runLivePipeline() async {
    final p = widget.params!;
    final ApiService api;
    if (widget.apiService != null) {
      api = widget.apiService!;
    } else {
      api = await ref.read(apiServiceProvider.future);
    }

    try {
      setState(() => _step = 0);

      // ── 1. Analyze (VLM) ────────────────────────────────────────────────
      List<Map<String, dynamic>> vlmOutput;
      if (p.isNewBook) {
        final List<Uint8List> imageBytes;
        final imagePaths = p.imageFilePaths;
        if (imagePaths != null && imagePaths.isNotEmpty) {
          imageBytes = await Future.wait(
            imagePaths.map((path) => File(path).readAsBytes()),
          );
        } else if (p.filePath.toLowerCase().endsWith('.pdf')) {
          imageBytes = await PdfService.pdfToJpegBytes(p.filePath);
        } else {
          imageBytes = [await File(p.filePath).readAsBytes()];
        }
        if (!mounted) return;

        final pages = await api.analyzePages(
          imageBytesList: imageBytes,
          vlmProvider: p.vlmProvider,
          processingMode: p.processingMode,
        );
        if (!mounted) return;

        await AppDatabase.instance.updateBookVlmOutput(
            p.bookId, jsonEncode(pages));
        vlmOutput = pages;
      } else {
        final book = await AppDatabase.instance.getBook(p.bookId);
        vlmOutput = List<Map<String, dynamic>>.from(
            jsonDecode(book!.vlmOutput) as List);
      }
      if (!mounted) return;
      setState(() => _step = 1);

      // ── 2. Script (LLM) ─────────────────────────────────────────────────
      final scriptMap = await api.generateScript(
        vlmOutput: vlmOutput,
        language: p.language,
        llmProvider: p.llmProvider,
        ttsProvider: p.ttsProvider,
      );
      if (!mounted) return;

      await AppDatabase.instance.updateAudioVersionStatus(
        p.versionId, 'generating',
        scriptJson: jsonEncode(scriptMap),
      );
      if (!mounted) return;
      setState(() => _step = 2);

      // ── 3. TTS ──────────────────────────────────────────────────────────
      final String audioDir;
      if (p.audioDirOverride != null) {
        audioDir = p.audioDirOverride!;
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        audioDir = path_pkg.join(docsDir.path, 'audio', p.versionId);
      }
      await Directory(audioDir).create(recursive: true);
      if (!mounted) return;

      final characters =
          List<Map<String, dynamic>>.from(scriptMap['characters'] as List);
      final lines =
          List<Map<String, dynamic>>.from(scriptMap['lines'] as List);
      final pendingLines = lines
          .where((l) =>
              l['status'] == 'pending' &&
              (l['index'] as int) > p.lastGeneratedLine)
          .map((l) {
            final charName = l['character'] as String;
            final defaultVoice =
                p.ttsProvider == 'gemini' ? 'Aoede' : 'alloy';
            final voice = characters.firstWhere(
              (c) => c['name'] == charName,
              orElse: () => {'voice': defaultVoice},
            )['voice'] as String;
            return {
              'index': l['index'],
              'text': l['text'],
              'voice': voice,
            };
          })
          .toList();

      final audioResults = await api.generateAudio(
        lines: pendingLines,
        ttsProvider: p.ttsProvider,
      );
      final scriptLines = List<Map<String, dynamic>>.from(lines);

      for (final result in audioResults) {
        final idx = result['index'] as int;
        final lineIdx = scriptLines.indexWhere((l) => l['index'] == idx);
        if (lineIdx == -1) continue; // skip if index not found
        if (result['status'] == 'ready') {
          final audioBytes = base64Decode(result['audio_b64'] as String);
          final fileName = 'line_${idx.toString().padLeft(3, '0')}.mp3';
          await File(path_pkg.join(audioDir, fileName)).writeAsBytes(audioBytes);
          scriptLines[lineIdx] = {...scriptLines[lineIdx], 'status': 'ready'};
        } else {
          scriptLines[lineIdx] = {...scriptLines[lineIdx], 'status': 'error'};
        }
        await AppDatabase.instance.updateAudioVersionStatus(
          p.versionId, 'generating',
          lastGeneratedLine: idx,
          scriptJson: jsonEncode({...scriptMap, 'lines': scriptLines}),
        );
      }
      if (!mounted) return;

      // Mark ready
      final existing =
          await AppDatabase.instance.getAudioVersion(p.versionId);
      if (existing != null) {
        await AppDatabase.instance.insertAudioVersion(
          AudioVersion(
            versionId: existing.versionId,
            bookId: existing.bookId,
            language: existing.language,
            llmProvider: existing.llmProvider,
            scriptJson: existing.scriptJson,
            audioDir: audioDir,
            status: 'ready',
            lastGeneratedLine: existing.lastGeneratedLine,
            lastPlayedLine: existing.lastPlayedLine,
            createdAt: existing.createdAt,
          ),
        );
      }
      if (!mounted) return;
      context.go('/player/${p.versionId}', extra: p.isNewBook);
    } on ApiException catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    } on PdfException catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _hasError ? _buildError() : _buildProgress(),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('✨', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 24),
        Text('Creating your audiobook...',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center),
        const SizedBox(height: 40),
        ..._steps.asMap().entries.map((entry) {
          final i = entry.key;
          final step = entry.value;
          final isDone = _step > i;
          final isCurrent = _step > 0 && _step == i;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: isCurrent
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          isDone
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: isDone ? Colors.green : Colors.grey),
                ),
                const SizedBox(width: 12),
                Text(
                  '${step.icon} ${step.label}',
                  style: TextStyle(
                    color: isDone
                        ? Colors.green
                        : (isCurrent ? null : Colors.grey),
                    fontWeight: isCurrent ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Shown for recoverable errors (network drop, API timeout).
  /// Fatal errors (VLM fail, LLM malformed output after 1 retry) use context.pop() instead.
  Widget _buildError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        const Text('Something went wrong',
            style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        const Text('Your progress was saved.',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            setState(() { _step = 0; _hasError = false; });
            if (widget.params != null) {
              _runLivePipeline();
            } else {
              _runMockPipeline();
            }
          },
          child: const Text('Try Again'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('Go Back'),
        ),
      ],
    );
  }
}
