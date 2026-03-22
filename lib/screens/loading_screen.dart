import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoadingScreen extends StatefulWidget {
  final String bookId;
  final String language;

  const LoadingScreen(
      {super.key, required this.bookId, required this.language});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
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
    _runMockPipeline();
  }

  Future<void> _runMockPipeline() async {
    for (int i = 0; i < _steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() => _step = i + 1);
    }
    if (!mounted) return;
    // Phase 2: always navigates to mock English version
    context.go('/player/mock_book_001_en');
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
            setState(() {
              _step = 0;
              _hasError = false;
            });
            _runMockPipeline();
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
