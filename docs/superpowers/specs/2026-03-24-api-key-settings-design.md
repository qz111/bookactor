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
| `apiServiceProvider` | `FutureProvider<ApiService>` | Builds `ApiService` with keys from `apiKeysProvider` |

`LoadingScreen` switches from constructing `ApiService(baseUrl: ...)` directly to watching `apiServiceProvider`. `LoadingParams` stays unchanged.

---

## UI — Settings Screen

**File:** `lib/screens/settings_screen.dart`

- Route: `/settings`
- Two `TextField` widgets, both obscured (password-style) with a show/hide toggle
- Labels: "OpenAI API Key", "Google API Key"
- On open: pre-fills fields with existing saved keys (if any)
- "Save" button: disabled until both fields are non-empty
- On save: calls `settingsService.saveKeys()`, invalidates `apiKeysProvider`, then:
  - On first launch: navigates to `/` (library)
  - On subsequent opens (via gear icon): pops back
- On save failure (`flutter_secure_storage` throws): shows `SnackBar("Failed to save keys. Please try again.")`

---

## Navigation & Enforcement

**Always-accessible entry point:**
- Gear icon (`Icons.settings`) added to the `AppBar` of `LibraryScreen` → pushes `/settings`

**First-launch redirect:**
- App starts at `/settings` by default (`initialLocation: '/settings'`)
- After saving keys, navigates to `/` (library)
- On subsequent launches, `app.dart` checks `hasKeys()` at startup; if true, `initialLocation` is `/`

This avoids async GoRouter `redirect` complexity — the initial location is determined once at app startup before the router is constructed, using a `FutureProvider` or a pre-loaded value in `main.dart`.

**Upload screen guard:**
- Generate button is already disabled by `_processingMode == null || _selectedFilePath == null`
- Add a third condition: `apiKeysProvider` is not yet loaded or keys are empty
- Hint text below the button when keys are missing: "Add API keys in Settings to generate."

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

Each method includes the relevant key(s) in the request body:

| Method | Added fields |
|---|---|
| `analyzePages()` | `openai_api_key`, `google_api_key` (multipart form fields) |
| `generateScript()` | `openai_api_key`, `google_api_key` (JSON body) |
| `generateAudio()` | `openai_api_key` (JSON body) |

---

## Backend Changes

### Routers

**`/analyze` (multipart form):**
- Accept new form fields: `openai_api_key: str`, `google_api_key: str`
- Pass both to `analyze_pages()`

**`/script` (JSON body):**
- Add `openai_api_key: str`, `google_api_key: str` to the Pydantic request model
- Pass both to `generate_script()`

**`/tts` (JSON body):**
- Add `openai_api_key: str` to the `TtsRequest` Pydantic model
- Pass to `generate_audio()`

### Services

**`vlm_service.py`:**
- `analyze_pages()` accepts `openai_api_key` and `google_api_key`
- Passes the relevant key to `litellm.completion(api_key=...)` based on provider:
  - `gpt4o` → `openai_api_key`
  - `gemini` → `google_api_key`

**`llm_service.py`:**
- `generate_script()` accepts `openai_api_key` and `google_api_key`
- Same routing logic as VLM service

**`tts_service.py`:**
- Remove the module-level `_tts_client = AsyncOpenAI(api_key=OPENAI_API_KEY)` singleton
- `generate_audio()` accepts `openai_api_key`
- Creates `AsyncOpenAI(api_key=openai_api_key)` per-request

### config.py / .env

`config.py` and `.env` remain for local dev convenience (env fallback). When keys are provided via request body, they take precedence. The backend no longer _requires_ `.env` to be populated.

---

## Error Handling

| Scenario | Handling |
|---|---|
| Keys missing at generate time | Generate button disabled; hint text: "Add API keys in Settings to generate." |
| Invalid key → backend 401/403 | Caught by existing `ApiException` handler in `_runLivePipeline()`; shows existing error screen |
| `flutter_secure_storage` save failure | `SnackBar("Failed to save keys. Please try again.")` |
| First-launch: app opens before keys are set | `initialLocation: '/settings'` ensures user lands on Settings |

---

## Files Changed

### Flutter

| File | Change |
|---|---|
| `lib/services/settings_service.dart` | **New** — `SettingsService` wrapping `flutter_secure_storage` |
| `lib/providers/settings_provider.dart` | **New** — `settingsServiceProvider`, `apiKeysProvider`, `apiServiceProvider` |
| `lib/screens/settings_screen.dart` | **New** — Settings UI with two key fields and Save button |
| `lib/services/api_service.dart` | Add `openAiKey`, `googleKey` constructor fields; include in request bodies |
| `lib/app.dart` | Add `/settings` route; dynamic `initialLocation` based on `hasKeys()` |
| `lib/screens/library_screen.dart` | Add gear icon to AppBar |
| `lib/screens/loading_screen.dart` | Switch to `apiServiceProvider` instead of constructing `ApiService` directly |
| `lib/screens/upload_screen.dart` | Add keys guard to Generate button; add hint text |
| `pubspec.yaml` | Add `flutter_secure_storage` dependency |

### Backend

| File | Change |
|---|---|
| `backend/routers/analyze.py` | Accept `openai_api_key`, `google_api_key` form fields |
| `backend/routers/script.py` | Add key fields to request model |
| `backend/routers/tts.py` | Add `openai_api_key` to `TtsRequest` |
| `backend/services/vlm_service.py` | Pass `api_key` to `litellm.completion()` |
| `backend/services/llm_service.py` | Pass `api_key` to `litellm.completion()` |
| `backend/services/tts_service.py` | Remove module-level client; create per-request `AsyncOpenAI` |

### Tests

| File | Change |
|---|---|
| `test/services/api_service_test.dart` | Add `openAiKey`, `googleKey` to `ApiService` constructor calls; assert keys sent in bodies |
| `test/screens/loading_screen_live_test.dart` | Update `_RecordingApiService` constructor and `apiServiceProvider` wiring |
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
