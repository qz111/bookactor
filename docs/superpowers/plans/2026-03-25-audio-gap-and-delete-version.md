# Audio Gap + Delete Audio Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Append 600ms silence between TTS audio lines at generation time, and allow users to delete audio versions from the Book Detail screen.

**Architecture:** Feature 1 modifies the Python TTS service to append silence via pydub before base64-encoding each audio chunk — transparent to Flutter. Feature 2 adds a `deleteAudioVersion` DB method and converts `BookDetailScreen` to `ConsumerStatefulWidget` so a long-press triggers a confirmation dialog that deletes files + DB record.

**Tech Stack:** Python/FastAPI + pydub (backend); Flutter/Riverpod + sqflite (frontend)

**Spec:** `docs/superpowers/specs/2026-03-25-audio-gap-and-delete-version.md`

---

## File Map

| File | Change |
|------|--------|
| `backend/requirements.txt` | Add `pydub` |
| `backend/services/tts_service.py` | Add `logging`/`pydub` imports, `_append_silence` helper, update 2 call sites |
| `backend/tests/test_tts_service.py` | **Create** — unit tests for `_append_silence` |
| `lib/db/database.dart` | Add `deleteAudioVersion` method |
| `test/db/database_test.dart` | Add test for `deleteAudioVersion` |
| `lib/screens/book_detail_screen.dart` | Convert to `ConsumerStatefulWidget`; add `_confirmDelete` method; wrap `ListTile`s in `GestureDetector` |
| `test/screens/book_detail_screen_test.dart` | Add test for delete long-press flow |

---

## Task 1: Add pydub dependency

**Files:**
- Modify: `backend/requirements.txt`

- [ ] **Step 1: Add pydub to requirements**

Open `backend/requirements.txt` and add `pydub` on a new line after the existing entries:

```
fastapi
uvicorn[standard]
litellm
openai
google-genai
python-multipart
python-dotenv
pydub
```

- [ ] **Step 2: Install and verify**

```bash
cd backend
pip install pydub
python -c "from pydub import AudioSegment; print('pydub ok')"
```

Expected: `pydub ok`

- [ ] **Step 3: Create `backend/conftest.py`** (makes `services` importable in pytest)

Create `backend/conftest.py`:

```python
import sys
import os

# Add backend/ to sys.path so tests can import `services.tts_service` etc.
sys.path.insert(0, os.path.dirname(__file__))
```

- [ ] **Step 4: Commit**

```bash
git add backend/requirements.txt backend/conftest.py
git commit -m "chore: add pydub dependency and pytest conftest for TTS tests"
```

---

## Task 2: Implement `_append_silence` in `tts_service.py`

**Files:**
- Create: `backend/tests/__init__.py` (empty, makes it a package)
- Create: `backend/tests/test_tts_service.py`
- Modify: `backend/services/tts_service.py`

### Step 2a: Write the failing test

- [ ] **Step 1: Create test directory and file**

Create `backend/tests/__init__.py` (empty file).

Create `backend/tests/test_tts_service.py`:

```python
import io
import wave
import struct
import pytest
from unittest.mock import patch, MagicMock


def _make_wav(duration_ms: int = 200, sample_rate: int = 24000) -> bytes:
    """Generate a minimal valid WAV with silence."""
    num_frames = int(sample_rate * duration_ms / 1000)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(b"\x00\x00" * num_frames)
    return buf.getvalue()


def _wav_duration_ms(wav_bytes: bytes) -> float:
    """Return duration in ms of a WAV file."""
    with wave.open(io.BytesIO(wav_bytes)) as w:
        return w.getnframes() / w.getframerate() * 1000


class TestAppendSilence:
    def test_wav_extends_duration(self):
        from backend.services.tts_service import _append_silence

        original = _make_wav(duration_ms=200)
        result = _append_silence(original, "wav", duration_ms=600)

        original_ms = _wav_duration_ms(original)
        result_ms = _wav_duration_ms(result)

        assert result_ms == pytest.approx(original_ms + 600, abs=50)

    def test_wav_returns_bytes(self):
        from backend.services.tts_service import _append_silence

        original = _make_wav()
        result = _append_silence(original, "wav")
        assert isinstance(result, bytes)
        assert len(result) > len(original)

    def test_fallback_on_error_returns_original(self):
        from backend.services.tts_service import _append_silence

        bad_bytes = b"not audio"
        result = _append_silence(bad_bytes, "wav")
        # Use identity check (`is`), not equality, to confirm the exact original
        # object is returned — not a copy with equal content.
        assert result is bad_bytes

    def test_mp3_calls_pydub(self):
        """MP3 path delegates to pydub; mock it to avoid ffmpeg dependency in CI."""
        from backend.services.tts_service import _append_silence

        mock_segment = MagicMock()
        mock_segment.frame_rate = 24000
        mock_combined = MagicMock()
        mock_segment.__add__ = MagicMock(return_value=mock_combined)

        fake_mp3 = b"fake_mp3_bytes"

        def fake_export(buf, format):
            buf.write(b"fake_mp3_with_silence")

        mock_combined.export = fake_export

        with patch("backend.services.tts_service.AudioSegment") as MockAS:
            MockAS.from_file.return_value = mock_segment
            MockAS.silent.return_value = MagicMock()

            result = _append_silence(fake_mp3, "mp3", duration_ms=600)

        MockAS.from_file.assert_called_once()
        MockAS.silent.assert_called_once_with(duration=600, frame_rate=24000)
        assert result == b"fake_mp3_with_silence"
```

- [ ] **Step 2: Run test — verify it fails**

```bash
python -m pytest backend/tests/test_tts_service.py -v
```

Run from the **repo root** (the `conftest.py` in `backend/` adds `backend/` to `sys.path` automatically).

Expected: `ImportError` or `AttributeError: module ... has no attribute '_append_silence'`

### Step 2b: Implement `_append_silence`

- [ ] **Step 3: Add imports and logger to `tts_service.py`**

Open `backend/services/tts_service.py`. At the top, after `import wave`, add:

```python
import logging
from pydub import AudioSegment

logger = logging.getLogger(__name__)
```

Note: `import io` is already present at line 2 — do not duplicate it.

- [ ] **Step 4: Add `_append_silence` helper after `_pcm_to_wav`**

After the `_pcm_to_wav` function (around line 22), add:

```python
def _append_silence(audio_bytes: bytes, fmt: str, duration_ms: int = 600) -> bytes:
    """Append silence to an audio chunk using pydub.

    WAV: uses Python's built-in wave module via pydub — no ffmpeg needed.
    MP3: requires ffmpeg on PATH.
    Falls back to original bytes and logs ERROR on any failure.
    """
    try:
        segment = AudioSegment.from_file(io.BytesIO(audio_bytes), format=fmt)
        silence = AudioSegment.silent(duration=duration_ms, frame_rate=segment.frame_rate)
        combined = segment + silence
        buf = io.BytesIO()
        combined.export(buf, format=fmt)
        return buf.getvalue()
    except Exception as e:
        logger.error("_append_silence failed (%s): %s — returning original audio", fmt, e)
        return audio_bytes
```

- [ ] **Step 5: Run tests — verify they pass**

```bash
python -m pytest backend/tests/test_tts_service.py -v
```

Run from the **repo root**.

Expected: all 4 tests PASS

- [ ] **Step 6: Commit**

```bash
git add backend/services/tts_service.py backend/tests/__init__.py backend/tests/test_tts_service.py
git commit -m "feat: add _append_silence helper to tts_service with tests"
```

---

## Task 3: Wire `_append_silence` into both TTS call sites

**Files:**
- Modify: `backend/services/tts_service.py` (2 call sites)
- Modify: `backend/tests/test_tts_service.py` (add call-site smoke tests)

### Step 3a: Write tests for call sites

- [ ] **Step 1: Add call-site tests to `test_tts_service.py`**

Append to `backend/tests/test_tts_service.py`:

```python
class TestGenerateOneOpenai:
    """Smoke test that _generate_one_openai passes audio through _append_silence."""

    def test_silence_appended_to_openai_result(self):
        from backend.services import tts_service

        # Fake MP3 bytes (pydub path is mocked)
        fake_mp3 = b"fake_mp3"
        fake_silenced = b"fake_mp3_silenced"

        mock_response = MagicMock()
        mock_response.content = fake_mp3

        mock_client = MagicMock()
        mock_client.audio.speech.create = MagicMock()

        import asyncio

        async def fake_create(**kwargs):
            return mock_response

        mock_client.audio.speech.create = fake_create

        with patch.object(tts_service, "_append_silence", return_value=fake_silenced) as mock_silence:
            result = asyncio.get_event_loop().run_until_complete(
                tts_service._generate_one_openai(mock_client, {"index": 0, "text": "Hello", "voice": "alloy"})
            )

        mock_silence.assert_called_once_with(fake_mp3, "mp3")
        import base64
        assert result["audio_b64"] == base64.b64encode(fake_silenced).decode()
        assert result["status"] == "ready"
        assert result["index"] == 0


class TestGenerateOneGemini:
    """Smoke test that _generate_one_gemini passes WAV through _append_silence."""

    def test_silence_appended_to_gemini_result(self):
        from backend.services import tts_service

        fake_wav = b"fake_wav"
        fake_silenced = b"fake_wav_silenced"

        # Mock the Gemini response structure
        mock_part = MagicMock()
        mock_part.inline_data.data = b"raw_pcm"
        mock_content = MagicMock()
        mock_content.parts = [mock_part]
        mock_candidate = MagicMock()
        mock_candidate.content = mock_content
        mock_response = MagicMock()
        mock_response.candidates = [mock_candidate]

        mock_client = MagicMock()
        mock_client.models.generate_content.return_value = mock_response

        import asyncio

        with patch.object(tts_service, "_pcm_to_wav", return_value=fake_wav), \
             patch.object(tts_service, "_append_silence", return_value=fake_silenced) as mock_silence:
            result = asyncio.get_event_loop().run_until_complete(
                tts_service._generate_one_gemini(mock_client, {"index": 1, "text": "Hi", "voice": "Aoede"})
            )

        mock_silence.assert_called_once_with(fake_wav, "wav")
        import base64
        assert result["audio_b64"] == base64.b64encode(fake_silenced).decode()
        assert result["status"] == "ready"
```

- [ ] **Step 2: Run tests — verify new tests fail**

```bash
python -m pytest backend/tests/test_tts_service.py::TestGenerateOneOpenai backend/tests/test_tts_service.py::TestGenerateOneGemini -v
```

Run from the **repo root**.

Expected: FAIL — `_append_silence` is not yet called at those sites.

### Step 3b: Update call sites

- [ ] **Step 3: Update `_generate_one_openai` in `tts_service.py`**

Find this line (currently around line 33):
```python
audio_b64 = base64.b64encode(response.content).decode()
```

Replace with:
```python
audio_b64 = base64.b64encode(_append_silence(response.content, "mp3")).decode()
```

- [ ] **Step 4: Update `_generate_one_gemini` in `tts_service.py`**

Find these two lines (currently around lines 59–60):
```python
wav_bytes = _pcm_to_wav(pcm_bytes)
audio_b64 = base64.b64encode(wav_bytes).decode()
```

Replace with:
```python
wav_bytes = _pcm_to_wav(pcm_bytes)
audio_b64 = base64.b64encode(_append_silence(wav_bytes, "wav")).decode()
```

- [ ] **Step 5: Run all backend tests — verify all pass**

```bash
python -m pytest backend/tests/test_tts_service.py -v
```

Run from the **repo root**.

Expected: all tests PASS (4 from Task 2 + 2 new call-site tests = 6 total)

- [ ] **Step 6: Commit**

```bash
git add backend/services/tts_service.py backend/tests/test_tts_service.py
git commit -m "feat: append 600ms silence to each TTS audio chunk at generation time"
```

---

## Task 4: Add `deleteAudioVersion` to the database

**Files:**
- Modify: `lib/db/database.dart`
- Modify: `test/db/database_test.dart`

### Step 4a: Write the failing test

- [ ] **Step 1: Add test to `test/db/database_test.dart`**

Inside the `group('AudioVersions', ...)` block, after the last existing `test(...)`, add:

```dart
test('deleteAudioVersion removes the row', () async {
  await db.insertAudioVersion(testVersion);

  // Verify it exists
  final before = await db.getAudioVersion('test123_en');
  expect(before, isNotNull);

  await db.deleteAudioVersion('test123_en');

  final after = await db.getAudioVersion('test123_en');
  expect(after, isNull);
});

test('deleteAudioVersion on missing id is a no-op', () async {
  // Should not throw
  await expectLater(
    db.deleteAudioVersion('nonexistent_id'),
    completes,
  );
});
```

- [ ] **Step 2: Run test — verify it fails**

```bash
flutter test test/db/database_test.dart
```

Expected: compile error — `deleteAudioVersion` not defined on `AppDatabase`.

### Step 4b: Implement

- [ ] **Step 3: Add `deleteAudioVersion` to `lib/db/database.dart`**

After the `getGeneratingVersions` method (end of file, around line 170), add:

```dart
Future<void> deleteAudioVersion(String versionId) async {
  final db = await database;
  await db.delete('audio_versions', where: 'version_id = ?', whereArgs: [versionId]);
}
```

- [ ] **Step 4: Run tests — verify all pass**

```bash
flutter test test/db/database_test.dart
```

Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/db/database.dart test/db/database_test.dart
git commit -m "feat: add deleteAudioVersion to AppDatabase"
```

---

## Task 5: Convert `BookDetailScreen` to `ConsumerStatefulWidget`

This task is a pure refactor — no behavior change. All existing tests must continue to pass.

**Files:**
- Modify: `lib/screens/book_detail_screen.dart`

- [ ] **Step 1: Convert the widget class declaration**

In `lib/screens/book_detail_screen.dart`, change:

```dart
class BookDetailScreen extends ConsumerWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
```

to:

```dart
class BookDetailScreen extends ConsumerStatefulWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  @override
  Widget build(BuildContext context) {
```

Note: `WidgetRef ref` is removed from `build` — it is now available as `ref` inherited from `ConsumerState`.

- [ ] **Step 2: Update all four helper method call sites inside `build`**

In the `build` method (now in `_BookDetailScreenState`), update **four** call sites — `_coverPlaceholder` appears at **two** places (errorBuilder fallback at line 46, and the null-path at line 48):

| Line | Old | New |
|------|-----|-----|
| ~46 | `_coverPlaceholder(context)` (errorBuilder) | `widget._coverPlaceholder(context)` |
| ~48 | `_coverPlaceholder(context)` (else branch) | `widget._coverPlaceholder(context)` |
| ~66 | `_languageName(v.language)` | `widget._languageName(v.language)` |
| ~79 | `_showNewLanguageSheet(context, book)` | `widget._showNewLanguageSheet(context, book)` |

The three helper methods `_coverPlaceholder`, `_languageName`, and `_showNewLanguageSheet` **stay on the `BookDetailScreen` widget class** unchanged. They're accessible from `_BookDetailScreenState` via `widget.` because Dart's `_` prefix is file-private, not class-private.

- [ ] **Step 3: Run existing tests — verify no regression**

```bash
flutter test test/screens/book_detail_screen_test.dart
```

Expected: all 3 existing tests PASS

- [ ] **Step 4: Commit**

```bash
git add lib/screens/book_detail_screen.dart
git commit -m "refactor: convert BookDetailScreen to ConsumerStatefulWidget"
```

---

## Task 6: Add delete UI and `_confirmDelete` method

**Files:**
- Modify: `lib/screens/book_detail_screen.dart`
- Modify: `test/screens/book_detail_screen_test.dart`

### Step 6a: Write the failing test

- [ ] **Step 1: Add delete tests to `test/screens/book_detail_screen_test.dart`**

Add these two `testWidgets` at the end of `main()`:

```dart
testWidgets('long-press on ready version shows delete dialog', (tester) async {
  final version = AudioVersion(
    versionId: 'detail_test_book_en',
    bookId: 'detail_test_book',
    language: 'en',
    scriptJson: '{}',
    audioDir: '',
    status: 'ready',
    lastGeneratedLine: 0,
    lastPlayedLine: 0,
    createdAt: 1711065600,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        singleBookProvider('detail_test_book').overrideWith((_) async => testBook),
        audioVersionsProvider('detail_test_book').overrideWith(
          (_) async => [version],
        ),
      ],
      child: const MaterialApp(
        home: BookDetailScreen(bookId: 'detail_test_book'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Long-press the English language tile
  await tester.longPress(find.text('English'));
  await tester.pumpAndSettle();

  expect(find.text('Delete audio version?'), findsOneWidget);
  expect(find.text('Delete'), findsOneWidget);
  expect(find.text('Cancel'), findsOneWidget);
});

testWidgets('long-press on generating version does NOT show delete dialog', (tester) async {
  final version = AudioVersion(
    versionId: 'detail_test_book_zh',
    bookId: 'detail_test_book',
    language: 'zh',
    scriptJson: '{}',
    audioDir: '',
    status: 'generating',
    lastGeneratedLine: 0,
    lastPlayedLine: 0,
    createdAt: 1711065600,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        singleBookProvider('detail_test_book').overrideWith((_) async => testBook),
        audioVersionsProvider('detail_test_book').overrideWith(
          (_) async => [version],
        ),
      ],
      child: const MaterialApp(
        home: BookDetailScreen(bookId: 'detail_test_book'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.longPress(find.text('Chinese (Simplified)'));
  await tester.pumpAndSettle();

  expect(find.text('Delete audio version?'), findsNothing);
});
```

- [ ] **Step 2: Run tests — verify new tests fail**

```bash
flutter test test/screens/book_detail_screen_test.dart
```

Expected: 2 new tests FAIL (long-press not wired up yet), 3 existing tests PASS.

### Step 6b: Implement delete UI

- [ ] **Step 3: Add `_confirmDelete` method to `_BookDetailScreenState`**

In `_BookDetailScreenState`, add before the `build` method:

```dart
void _confirmDelete(BuildContext screenContext, AudioVersion version) {
  showDialog(
    context: screenContext,
    builder: (dialogContext) {
      bool deleting = false;
      return StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Delete audio version?'),
          content: const Text(
            'This will permanently delete all audio files for this language. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: deleting
                  ? null
                  : () async {
                      setDialogState(() => deleting = true);
                      bool success = false;
                      try {
                        if (version.audioDir.isNotEmpty) {
                          try {
                            await Directory(version.audioDir)
                                .delete(recursive: true);
                          } on FileSystemException {
                            // Directory already gone — proceed to DB cleanup.
                          }
                        }
                        await AppDatabase.instance
                            .deleteAudioVersion(version.versionId);
                        success = true;
                      } finally {
                        if (!success && mounted) {
                          setDialogState(() => deleting = false);
                        }
                      }
                      if (success && mounted) {
                        ref.invalidate(audioVersionsProvider(widget.bookId));
                        Navigator.pop(dialogContext);
                      }
                    },
              child: deleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Delete'),
            ),
          ],
        ),
      );
    },
  );
}
```

- [ ] **Step 4: Wrap each `ListTile` in a `GestureDetector`**

In the `build` method, find the `versions.map((v) => ListTile(...))` expression (inside `data: (versions) => Column(...)`).

Replace:
```dart
...versions.map((v) => ListTile(
      leading: LanguageBadge(language: v.language, status: v.status),
      title: Text(widget._languageName(v.language)),
      subtitle: Text(v.status),
      trailing: v.status == 'ready'
          ? IconButton(
              icon: const Icon(Icons.play_circle_filled),
              onPressed: () => context.push('/player/${v.versionId}'),
            )
          : null,
    )),
```

with:
```dart
...versions.map((v) => GestureDetector(
      onLongPress: v.status == 'generating'
          ? null
          : () => _confirmDelete(context, v),
      child: ListTile(
        leading: LanguageBadge(language: v.language, status: v.status),
        title: Text(widget._languageName(v.language)),
        subtitle: Text(v.status),
        trailing: v.status == 'ready'
            ? IconButton(
                icon: const Icon(Icons.play_circle_filled),
                onPressed: () => context.push('/player/${v.versionId}'),
              )
            : null,
      ),
    )),
```

- [ ] **Step 5: Run all tests — verify all pass**

```bash
flutter test test/screens/book_detail_screen_test.dart
```

Expected: all 5 tests PASS (3 existing + 2 new)

- [ ] **Step 6: Run full test suite**

```bash
flutter test
```

Expected: all tests PASS with no regressions.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/book_detail_screen.dart test/screens/book_detail_screen_test.dart
git commit -m "feat: add long-press delete for audio versions with confirmation dialog"
```

---

## Done

Both features are complete. Manual smoke test checklist:
- [ ] Generate a new audiobook (OpenAI TTS) and verify audible gap between lines during playback
- [ ] Generate a new audiobook (Gemini TTS) and verify audible gap
- [ ] Long-press a `ready` audio version → delete dialog appears → tap Delete → version disappears from list
- [ ] Long-press a `generating` audio version → nothing happens
- [ ] Tap Cancel in the delete dialog → version is not deleted
