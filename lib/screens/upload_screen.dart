import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path_pkg;
import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import '../mock/mock_data.dart';
import '../models/audio_version.dart';
import '../models/book.dart';
import '../models/processing_mode.dart';
import '../providers/settings_provider.dart';
import '../screens/loading_screen.dart';
import '../services/pdf_service.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key}) : initialImagePaths = const [];

  /// Test-only constructor that pre-seeds image paths.
  @visibleForTesting
  const UploadScreen.withImages({
    super.key,
    required this.initialImagePaths,
  });

  final List<String> initialImagePaths;

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  String? _pdfPath;
  List<String> _imagePaths = [];
  String _language = 'en';
  String _vlmProvider = 'gemini';
  String _llmProvider = 'gpt4o';
  String _ttsProvider = 'openai';
  bool _isGenerating = false;
  ProcessingMode? _processingMode;

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePaths.isNotEmpty) {
      _imagePaths = List<String>.from(widget.initialImagePaths);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final hasPdf = result.files.any(
      (f) => f.name.toLowerCase().endsWith('.pdf'),
    );

    setState(() {
      if (hasPdf) {
        // Use first PDF; ignore any other files in this pick.
        final pdfFile = result.files.firstWhere(
          (f) => f.name.toLowerCase().endsWith('.pdf'),
        );
        _pdfPath = pdfFile.path;
        _imagePaths = [];
      } else {
        _pdfPath = null;
        final newPaths = result.files
            .where((f) => f.path != null)
            .map((f) => f.path!)
            .toList();
        // Build merged list with deduplication, then assign once.
        final merged = List<String>.from(_imagePaths);
        final seen = Set<String>.from(merged);
        for (final p in newPaths) {
          if (seen.add(p)) merged.add(p);
        }
        _imagePaths = merged.length > 50 ? merged.sublist(0, 50) : merged;
        // Show cap SnackBar if needed.
        if (merged.length > 50) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Maximum 50 images supported. Extra images were removed.',
                  ),
                ),
              );
            }
          });
        }
      }
    });
  }

  Future<void> _generate() async {
    final isMultiImage = _imagePaths.isNotEmpty;
    if ((!isMultiImage && _pdfPath == null) || _processingMode == null) return;
    setState(() => _isGenerating = true);
    try {
      // ── Build primary path and pagesDir ─────────────────────────────────
      final String primaryPath;
      final String bookTitle;
      final String pagesDir;
      if (isMultiImage) {
        primaryPath = _imagePaths.first;
        bookTitle = path_pkg.basename(_imagePaths.first);
        pagesDir = jsonEncode(_imagePaths);
      } else {
        primaryPath = _pdfPath!;
        bookTitle = path_pkg.basename(_pdfPath!);
        pagesDir = _pdfPath!;
      }

      // ── Compute book ID ──────────────────────────────────────────────────
      final List<Uint8List> allBytes;
      if (isMultiImage) {
        allBytes = await Future.wait(
          _imagePaths.map((p) => File(p).readAsBytes()),
        );
      } else {
        allBytes = [await File(_pdfPath!).readAsBytes()];
      }
      final combined =
          Uint8List.fromList(allBytes.expand((b) => b).toList());
      final bookId = sha256.convert(combined).toString();

      // ── Persist book row ─────────────────────────────────────────────────
      await AppDatabase.instance.insertBook(Book(
        bookId: bookId,
        title: bookTitle,
        coverPath: null,
        pagesDir: pagesDir,
        vlmOutput: '',
        vlmProvider: _vlmProvider,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ));

      // ── Cover extraction (non-fatal) ─────────────────────────────────────
      try {
        final dir = await getApplicationDocumentsDirectory();
        final coverFile = File('${dir.path}/${bookId}_cover.jpg');
        if (isMultiImage) {
          await coverFile.writeAsBytes(allBytes.first);
          await AppDatabase.instance.updateBookCoverPath(
              bookId, coverFile.path);
        } else {
          final pages = await PdfService.pdfToJpegBytes(_pdfPath!);
          if (pages.isNotEmpty) {
            await coverFile.writeAsBytes(pages.first);
            await AppDatabase.instance.updateBookCoverPath(
                bookId, coverFile.path);
          }
        }
      } catch (e) {
        debugPrint('Cover extraction failed (non-fatal): $e');
      }

      // ── Insert audio version placeholder ─────────────────────────────────
      final versionId = '${bookId}_$_language';
      await AppDatabase.instance.insertAudioVersion(AudioVersion(
        versionId: versionId,
        bookId: bookId,
        language: _language,
        llmProvider: _llmProvider,
        ttsProvider: _ttsProvider,
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
          filePath: primaryPath,
          language: _language,
          vlmProvider: _vlmProvider,
          llmProvider: _llmProvider,
          ttsProvider: _ttsProvider,
          processingMode: _processingMode!,
          isNewBook: true,
          lastGeneratedLine: -1,
          imageFilePaths: isMultiImage ? _imagePaths : null,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keysAsync = ref.watch(apiKeysProvider);
    final hasKeys = keysAsync.valueOrNull != null &&
        keysAsync.valueOrNull!.openAi.isNotEmpty &&
        keysAsync.valueOrNull!.google.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Book'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Home',
          onPressed: () => context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'What kind of book is this?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ModeCard(
                  icon: '📝',
                  label: 'Text-Heavy',
                  subtitle: 'Story told through words',
                  selected: _processingMode == ProcessingMode.textHeavy,
                  onTap: () => setState(() => _processingMode = ProcessingMode.textHeavy),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeCard(
                  icon: '🖼️',
                  label: 'Picture Book',
                  subtitle: 'Story told through illustrations',
                  selected: _processingMode == ProcessingMode.pictureBook,
                  onTap: () => setState(() => _processingMode = ProcessingMode.pictureBook),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildUploadArea(),
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
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _ttsProvider,
            decoration: const InputDecoration(
                labelText: 'Text-to-Speech (TTS)',
                border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'openai', child: Text('OpenAI TTS')),
              DropdownMenuItem(value: 'gemini', child: Text('Gemini TTS')),
            ],
            onChanged: (v) => setState(() => _ttsProvider = v!),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: (!hasKeys ||
                    (_pdfPath == null && _imagePaths.isEmpty) ||
                    _processingMode == null ||
                    _isGenerating)
                ? null
                : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate Audiobook'),
          ),
          if (!hasKeys) ...[
            const SizedBox(height: 8),
            Text(
              'Add API keys in Settings to generate.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadArea() {
    // ── Multi-image state ────────────────────────────────────────────────
    if (_imagePaths.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ReorderableListView(
              shrinkWrap: true,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _imagePaths.removeAt(oldIndex);
                  _imagePaths.insert(newIndex, item);
                });
              },
              children: [
                for (int i = 0; i < _imagePaths.length; i++)
                  _ImageRow(
                    key: ValueKey(_imagePaths[i]),
                    index: i,
                    path: _imagePaths[i],
                    onDelete: () =>
                        setState(() => _imagePaths.removeAt(i)),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add more images'),
          ),
        ],
      );
    }

    // ── PDF selected / empty state ───────────────────────────────────────
    return GestureDetector(
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
              Text(
                _pdfPath != null
                    ? path_pkg.basename(_pdfPath!)
                    : 'Tap to select PDF or images',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? color.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _ImageRow extends StatelessWidget {
  final int index;
  final String path;
  final VoidCallback onDelete;

  const _ImageRow({
    required super.key,
    required this.index,
    required this.path,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Page number badge
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(path),
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 50,
                height: 50,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image, size: 24),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        path_pkg.basename(path),
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: onDelete,
            tooltip: 'Remove',
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle),
          ),
        ],
      ),
    );
  }
}
