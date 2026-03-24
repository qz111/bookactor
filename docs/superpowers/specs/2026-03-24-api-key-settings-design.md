# API Key Settings — Design Spec

**Date:** 2026-03-24
**Status:** Approved

---

## Overview

Users enter their OpenAI and Google API keys once via a Settings screen. Keys are stored securely in the OS credential store (`flutter_secure_storage`). On every AI API call, the Flutter client reads the keys and sends them in the request body to the local backend. The backend uses the provided keys directly instead of reading from `.env`.

---

## Storage — SettingsService (Flutter)

A new `lib/services/settings_service.dart` wraps `flutter_secure_storage` with four methods:

```dart
Future<bool> hasKeys()
Future<({String openAi, String google})> getKeys()
Future<void> saveKeys({required String openAiKey, required String googleKey})
Future<void> clearKeys()
```

Storage keys: `openai_api_key`, `google_api_key`.

`hasKeys()` returns `true` only if both values are saved and non-empty.

**Why flutter_secure_storage:** Keys are stored in the OS credential store (Windows Credential Manager on Windows, Keychain on iOS/macOS). Never written to a plain file on disk. Encrypted and tied to the user account.

**Transport security:** The backend runs on localhost (`127.0.0.1`). Traffic never leaves the machine, so plain text in the HTTP body is sufficient. No encoding or encryption in transit is required.

---

## Providers (Flutter)

Three new Riverpod providers in `lib/providers/settings_provider.dart`:

| Provider | Type | Purpose |
|---|---|---|
| `settingsServiceProvider` | `Provider<SettingsService>` | Singleton service instance |
| `apiKeysProvider` | `FutureProvider<({String openAi, String google})>` | Loads keys from secure storage; invalidated after `saveKeys()` |
| `apiServiceProvider` | `FutureProvider<ApiService>` | Builds `ApiService(baseUrl: 'http://localhost:8000', openAiKey: keys.openAi, googleKey: keys.google)` from `apiKeysProvider` |
| `initialLocationProvider` | `Provider<String>` | Initial GoRouter location; overridden in `main.dart` with pre-loaded `hasKeys()` result |

### ApiService wiring in LoadingScreen

`LoadingScreen` becomes a `ConsumerStatefulWidget` and its state class becomes `ConsumerState<LoadingScreen>` (giving `ref` access in all state methods). The existing optional `ApiService? apiService` constructor parameter is **retained** for test injection. `_runLivePipeline` resolves the service as follows:

```dart
final api = widget.apiService ?? await ref.read(apiServiceProvider.future);
```

This preserves backward compatibility with `loading_screen_live_test.dart`, which passes `apiService: fakeApi` directly. No provider override is required in that test — the constructor injection path continues to work unchanged.

---

## UI — Settings Screen

**File:** `lib/screens/settings_screen.dart`

- Route: `/settings`
- Two `TextField` widgets, both obscured (password-style) with a show/hide toggle
- Labels: "OpenAI API Key", "Google API Key"
- On open: pre-fills fields by watching `ref.watch(apiKeysProvider)` — when the async value resolves, the controllers are populated with existing saved keys (if any)
- "Save" button: disabled until both fields are non-empty
- On save: calls `settingsService.saveKeys()`, invalidates `apiKeysProvider`, then:
  - On first launch: navigates to `/` (library)
  - On subsequent opens (via gear icon): pops back
- On save failure (`flutter_secure_storage` throws): shows `SnackBar("Failed to save keys. Please try again.")`

---

## Navigation & Enforcement

### First-launch redirect

`main.dart` awaits `SettingsService().hasKeys()` **before** calling `runApp()`. The boolean result is passed to `BookActorApp` and forwarded to `routerProvider` as a constructor argument (or via a `Provider<bool>` override). `routerProvider` uses it to set `initialLocation`:

```dart
// In main.dart — SettingsService() is constructed once here before runApp().
// A second instance is created later by settingsServiceProvider at runtime.
// This is safe because flutter_secure_storage reads from the OS store on every
// call; there is no in-memory state to keep in sync between the two instances.
final hasKeys = await SettingsService().hasKeys();
runApp(ProviderScope(
  overrides: [initialLocationProvider.overrideWithValue(hasKeys ? '/' : '/settings')],
  child: const BookActorApp(),
));

// In app.dart — imports initialLocationProvider from lib/providers/settings_provider.dart
final routerProvider = Provider<GoRouter>((ref) {
  final initialLocation = ref.watch(initialLocationProvider);
  return GoRouter(
    initialLocation: initialLocation,
    routes: [...],
  );
});

// In lib/providers/settings_provider.dart
final initialLocationProvider = Provider<String>((_) => '/');
```

On subsequent launches where keys are already saved, the app opens directly at `/` (library). No async redirect is needed at runtime.

### Always-accessible entry point

Gear icon (`Icons.settings`) added to the `AppBar` of `LibraryScreen` → pushes `/settings`.

### Upload screen guard

`UploadScreen` is already a `ConsumerStatefulWidget`. The Generate button guard adds a third condition using `ref.watch(apiKeysProvider)`:

```dart
final keysAsync = ref.watch(apiKeysProvider);
final hasKeys = keysAsync.valueOrNull != null &&
    keysAsync.valueOrNull!.openAi.isNotEmpty &&
    keysAsync.valueOrNull!.google.isNotEmpty;

onPressed: (!hasKeys || _selectedFilePath == null || _processingMode == null || _isGenerating)
    ? null
    : _generate,
```

Hint text below the button when keys are missing: "Add API keys in Settings to generate."

### Resume navigation (LibraryScreen)

The cold-start resume flow in `LibraryScreen` constructs `LoadingParams` and pushes `/loading` unchanged. Key injection is handled inside `LoadingScreen` via `apiServiceProvider` — the resume path is unaffected.

---

## ApiService Changes (Flutter)

`ApiService` gains two constructor fields:

```dart
ApiService({
  required this.baseUrl,
  required this.openAiKey,
  required this.googleKey,
  http.Client? client,
})
```

Each method reads keys from `this.openAiKey` / `this.googleKey` (constructor fields) and includes them in the request body. No new method-level parameters are added to `analyzePages()`, `generateScript()`, or `generateAudio()`.

| Method | Added body fields (sent from constructor fields) |
|---|---|
| `analyzePages()` | `openai_api_key`, `google_api_key` (multipart form fields) |
| `generateScript()` | `openai_api_key`, `google_api_key` (JSON body) |
| `generateAudio()` | `openai_api_key` (JSON body) |

---

## Backend Changes

### Routers

**`/analyze` (multipart form):**
- The Flutter client already sends `processing_mode` as a form field (added in the processing-mode-selection feature), but the backend router and `vlm_service.py` do not yet accept or use it. This gap is resolved as part of this feature.
- Final accepted form fields: `vlm_provider`, `processing_mode`, `openai_api_key`, `google_api_key`
- Passes `processing_mode` and the relevant key to `analyze_pages()`

**`/script` (JSON body):**
- Add `openai_api_key: str`, `google_api_key: str` to the Pydantic request model
- Pass both to `generate_script()`

**`/tts` (JSON body):**
- Add `openai_api_key: str` to the `TtsRequest` Pydantic model
- Pass to `generate_audio()`

### Services

**`vlm_service.py`:**
- `analyze_pages()` accepts `processing_mode: str`, `openai_api_key: str`, and `google_api_key: str`
- Uses `processing_mode` to select the appropriate VLM prompt strategy (OCR-focused for `text_heavy`, visual-narrative for `picture_book`)
- Passes the relevant key to `litellm.completion(api_key=...)` based on provider:
  - `gpt4o` → `openai_api_key`
  - `gemini` → `google_api_key`

**`llm_service.py`:**
- `generate_script()` accepts `openai_api_key: str` and `google_api_key: str`
- Same routing logic as VLM service

**`tts_service.py`:**
- Remove the module-level `_tts_client = AsyncOpenAI(api_key=OPENAI_API_KEY)` singleton
- `generate_audio()` accepts `openai_api_key: str`
- Creates `AsyncOpenAI(api_key=openai_api_key)` **once** inside `generate_audio()` and passes it down to `_generate_one(client, line)` — one client per request, not one per line

### config.py / .env

`config.py` and `.env` remain for local dev convenience (env fallback). When keys are provided via request body, they take precedence. The backend no longer _requires_ `.env` to be populated.

---

## Error Handling

| Scenario | Handling |
|---|---|
| Keys missing at generate time | Generate button disabled; hint text: "Add API keys in Settings to generate." |
| Invalid key → backend 401/403 | Caught by existing `ApiException` handler in `_runLivePipeline()`; shows existing error screen |
| `flutter_secure_storage` save failure | `SnackBar("Failed to save keys. Please try again.")` |
| First-launch: app opens before keys are set | `initialLocation: '/settings'` via pre-loaded `hasKeys()` in `main.dart` |

---

## Files Changed

### Flutter

| File | Change |
|---|---|
| `lib/services/settings_service.dart` | **New** — `SettingsService` wrapping `flutter_secure_storage` |
| `lib/providers/settings_provider.dart` | **New** — `settingsServiceProvider`, `apiKeysProvider`, `apiServiceProvider`, `initialLocationProvider` |
| `lib/screens/settings_screen.dart` | **New** — Settings UI with two key fields and Save button |
| `lib/services/api_service.dart` | Add `openAiKey`, `googleKey` constructor fields; include in request bodies |
| `lib/main.dart` | Await `hasKeys()` before `runApp()`; pass result via `initialLocationProvider` override |
| `lib/app.dart` | Add `/settings` route; `routerProvider` reads `initialLocationProvider` |
| `lib/screens/library_screen.dart` | Add gear icon to AppBar |
| `lib/screens/loading_screen.dart` | Becomes `ConsumerStatefulWidget`; `_runLivePipeline` resolves `ApiService` via `widget.apiService ?? await ref.read(apiServiceProvider.future)` |
| `lib/screens/upload_screen.dart` | Add `apiKeysProvider` guard to Generate button via `ref.watch(apiKeysProvider).valueOrNull`; add hint text |
| `pubspec.yaml` | Add `flutter_secure_storage` dependency |

### Backend

| File | Change |
|---|---|
| `backend/routers/analyze.py` | Add `openai_api_key`, `google_api_key` form fields (retain `vlm_provider`, `processing_mode`) |
| `backend/routers/script.py` | Add `openai_api_key`, `google_api_key` to request model |
| `backend/routers/tts.py` | Add `openai_api_key` to `TtsRequest` |
| `backend/services/vlm_service.py` | Accept and pass `api_key` to `litellm.completion()` |
| `backend/services/llm_service.py` | Accept and pass `api_key` to `litellm.completion()` |
| `backend/services/tts_service.py` | Remove module-level client; create per-request client in `generate_audio()`, pass to `_generate_one()` |

### Tests

| File | Change |
|---|---|
| `test/services/api_service_test.dart` | Add `openAiKey`, `googleKey` to `ApiService` constructor calls; assert keys sent in request bodies |
| `test/screens/loading_screen_live_test.dart` | `LoadingScreen` is now `ConsumerStatefulWidget` (no test change needed for this); `_RecordingApiService` subclass is retained and passed via existing `apiService:` constructor param. Update `_RecordingApiService`'s super constructor call: `super(baseUrl: 'http://fake', openAiKey: 'test', googleKey: 'test')` |
| `tests/test_analyze.py` | Add `openai_api_key`, `google_api_key` to test requests |
| `tests/test_script.py` | Add keys to test requests |
| `tests/test_tts.py` | Add `openai_api_key` to test requests |
| `tests/services/test_vlm_service.py` | Update `analyze_pages()` call signatures |
| `tests/services/test_llm_service.py` | Update `generate_script()` call signatures |
| `tests/services/test_tts_service.py` | Update `generate_audio()` call signatures |

---

## Out of Scope

- HTTPS / TLS for the local backend
- Per-book provider key selection
- Key validation / connection test on the Settings screen
- Key rotation or multiple key profiles
