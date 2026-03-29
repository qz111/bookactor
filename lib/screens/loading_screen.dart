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
import '../models/script.dart';
import '../services/api_service.dart';
import '../services/pdf_service.dart';

enum ResumeStage { vlm, llm, tts }

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
  /// Optional override for the audio output directory (useful in tests).
  final String? audioDirOverride;
  /// Optional list of image paths for multi-image mode.
  /// When non-null and non-empty, these files are read in order instead of [filePath].
  final List<String>? imageFilePaths;
  /// When non-null, the pipeline skips stages before this stage.
  /// null = run all stages from the beginning.
  final ResumeStage? startStage;
  /// Pre-loaded scriptJson for TTS resume (startStage=tts). When set, the
  /// pipeline uses this instead of reading from DB. Safe to pass because
  /// no prior stages modify scriptJson during a TTS-only resume run.
  final String? scriptJsonForResume;

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
    this.audioDirOverride,
    this.imageFilePaths,
    this.startStage,
    this.scriptJsonForResume,
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

      final bool runVlm = p.isNewBook || p.startStage == ResumeStage.vlm;
      // startStage==null means new-language run (isNewBook=false): skip VLM, run LLM.
      final bool runLlm =
          runVlm || p.startStage == null || p.startStage == ResumeStage.llm;

      // ── 1. Analyze (VLM) ────────────────────────────────────────────────
      List<Map<String, dynamic>> vlmOutput = const [];
      if (runVlm) {
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

        await AppDatabase.instance.updateBookVlmOutput(p.bookId, jsonEncode(pages));
        // Clear stale script so LLM writes a fresh one
        await AppDatabase.instance.updateAudioVersionStatus(
          p.versionId, 'generating', scriptJson: '{}');
        // Delete stale audio files — new LLM may produce a different chunk count
        final String audioDirToDelete;
        if (p.audioDirOverride != null) {
          audioDirToDelete = p.audioDirOverride!;
        } else {
          final docsDir = await getApplicationDocumentsDirectory();
          audioDirToDelete = path_pkg.join(docsDir.path, 'audio', p.versionId);
        }
        final deleteDir = Directory(audioDirToDelete);
        if (deleteDir.existsSync()) {
          await deleteDir.delete(recursive: true);
        }
        vlmOutput = pages;
      } else if (runLlm) {
        // Only needed when generateScript will be called
        final book = await AppDatabase.instance.getBook(p.bookId);
        vlmOutput = List<Map<String, dynamic>>.from(
            jsonDecode(book!.vlmOutput) as List);
      }
      // When runLlm=false (TTS resume): vlmOutput stays [] — generateScript is skipped
      if (!mounted) return;
      setState(() => _step = 1);

      // ── 2. Script (LLM) ─────────────────────────────────────────────────
      Map<String, dynamic> scriptMap;
      if (runLlm) {
        scriptMap = await api.generateScript(
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
      } else {
        // TTS resume: no prior stages modified scriptJson.
        // Use scriptJsonForResume if provided (already fresh from DB at nav time);
        // otherwise fall back to a DB read.
        if (p.scriptJsonForResume != null) {
          scriptMap = jsonDecode(p.scriptJsonForResume!) as Map<String, dynamic>;
        } else {
          final version = await AppDatabase.instance.getAudioVersion(p.versionId);
          scriptMap = jsonDecode(version!.scriptJson) as Map<String, dynamic>;
        }
      }
      if (!mounted) return;
      setState(() => _step = 2);

      // ── 3. TTS ──────────────────────────────────────────────────────────
      // Compute audioDir independently — DB value may be '' if version never completed
      final String audioDir;
      if (p.audioDirOverride != null) {
        audioDir = p.audioDirOverride!;
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        audioDir = path_pkg.join(docsDir.path, 'audio', p.versionId);
      }
      await Directory(audioDir).create(recursive: true);
      if (!mounted) return;

      final script = Script.fromJson(jsonEncode(scriptMap));
      final allChunks =
          List<Map<String, dynamic>>.from(scriptMap['chunks'] as List);

      // Build list of chunks that actually need generating.
      // Chunks with status='ready' and an existing file on disk are skipped.
      final chunksToGenerate = <Map<String, dynamic>>[];
      for (final c in allChunks) {
        if (c['status'] == 'ready') {
          final fileName =
              'chunk_${(c['index'] as int).toString().padLeft(3, '0')}.wav';
          if (File(path_pkg.join(audioDir, fileName)).existsSync()) {
            continue; // already done
          }
        }
        chunksToGenerate.add(c);
      }

      final pendingChunks = chunksToGenerate.map((c) {
        final speakers = List<String>.from(c['speakers'] as List);
        final voiceMap = {for (final s in speakers) s: script.voiceFor(s)};
        return {
          'index': c['index'],
          'text': c['text'],
          'voice_map': voiceMap,
        };
      }).toList();

      final audioResults = await api.generateAudio(
        chunks: pendingChunks,
        ttsProvider: p.ttsProvider,
      );

      // scriptChunks is the mutable working copy — starts from allChunks
      // so already-ready skipped chunks are preserved in the final JSON
      final scriptChunks = List<Map<String, dynamic>>.from(allChunks);

      for (final result in audioResults) {
        final idx = result['index'] as int;
        final chunkIdx = scriptChunks.indexWhere((c) => c['index'] == idx);
        if (chunkIdx == -1) continue;

        if (result['status'] == 'ready') {
          final audioBytes = base64Decode(result['audio_b64'] as String);
          final fileName = 'chunk_${idx.toString().padLeft(3, '0')}.wav';
          await File(path_pkg.join(audioDir, fileName)).writeAsBytes(audioBytes);
          scriptChunks[chunkIdx] = {
            ...scriptChunks[chunkIdx],
            'status': 'ready',
            'duration_ms': result['duration_ms'] as int,
          };
        } else {
          scriptChunks[chunkIdx] = {
            ...scriptChunks[chunkIdx],
            'status': 'error',
          };
        }
        await AppDatabase.instance.updateAudioVersionStatus(
          p.versionId, 'generating',
          scriptJson: jsonEncode({...scriptMap, 'chunks': scriptChunks}),
        );
      }

      // If any chunk failed, show error screen.
      // AudioVersion.status stays 'generating' — cold restart will flip it to 'error'
      // so the Retry/Resume button appears on the version card.
      if (scriptChunks.any((c) => c['status'] == 'error')) {
        if (!mounted) return;
        setState(() => _hasError = true);
        return;
      }

      // All chunks ready — mark version complete
      final existing = await AppDatabase.instance.getAudioVersion(p.versionId);
      if (existing != null) {
        await AppDatabase.instance.insertAudioVersion(
          AudioVersion(
            versionId: existing.versionId,
            bookId: existing.bookId,
            language: existing.language,
            llmProvider: existing.llmProvider,
            scriptJson: jsonEncode({...scriptMap, 'chunks': scriptChunks}),
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
