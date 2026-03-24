import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _openAiController = TextEditingController();
  final _googleController = TextEditingController();
  bool _showOpenAi = false;
  bool _showGoogle = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingKeys();
  }

  Future<void> _loadExistingKeys() async {
    final keys = await ref.read(settingsServiceProvider).getKeys();
    if (!mounted) return;
    _openAiController.text = keys.openAi;
    _googleController.text = keys.google;
    setState(() {}); // Recompute canSave so Save button enables when keys are pre-filled.
  }

  @override
  void dispose() {
    _openAiController.dispose();
    _googleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(settingsServiceProvider).saveKeys(
            openAiKey: _openAiController.text.trim(),
            googleKey: _googleController.text.trim(),
          );
      ref.invalidate(apiKeysProvider);
      if (!mounted) return;
      // Use canPop() to detect first launch (no back stack) vs gear-icon open.
      // On first launch, initialLocation is '/settings' with no prior route.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } catch (e, st) {
      debugPrint('SettingsScreen._save failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save keys. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _openAiController.text.trim().isNotEmpty &&
        _googleController.text.trim().isNotEmpty;
    // Hide back button when there is nowhere to go back to (first launch).
    final hasBackStack = context.canPop();

    return Scaffold(
      appBar: AppBar(
        title: const Text('API Keys'),
        automaticallyImplyLeading: hasBackStack,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (!hasBackStack) ...[
            const Text(
              'Enter your API keys to get started.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
          ],
          TextField(
            controller: _openAiController,
            obscureText: !_showOpenAi,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'OpenAI API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showOpenAi ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showOpenAi = !_showOpenAi),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _googleController,
            obscureText: !_showGoogle,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Google API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showGoogle ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showGoogle = !_showGoogle),
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: (canSave && !_saving) ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
