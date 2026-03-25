# Spec: Audio Gap Between TTS Lines + Delete Audio Version

**Date:** 2026-03-25
**Status:** Approved

---

## Summary

Two independent features:
1. Append a 600ms silence gap to each TTS-generated audio chunk so voices and tones don't bleed together during playback.
2. Allow users to delete an audio version (DB record + audio files on disk) from the Book Detail screen.

---

## Feature 1: Audio Gap at Generation Time

### Problem

Audio lines are played back-to-back with no gap. When different characters/voices are used, the immediate transition causes tones to bleed into each other and voices to feel collapsed.

### Solution

Append 600ms of silence to each audio chunk in `backend/services/tts_service.py` at generation time. The silence is baked into each file permanently. No Flutter or API changes required.

### Implementation

**File:** `backend/services/tts_service.py`

Add two lines near the top of the module (after existing imports; `io` is already imported — do not duplicate it):
```python
import logging
from pydub import AudioSegment

logger = logging.getLogger(__name__)
```

Add helper function:
```python
def _append_silence(audio_bytes: bytes, fmt: str, duration_ms: int = 600) -> bytes:
    """Append silence to the end of an audio chunk. Uses pydub for both MP3 and WAV.
    WAV processing uses Python's built-in wave module via pydub — no ffmpeg required.
    MP3 processing requires ffmpeg on PATH.
    Falls back to original bytes and logs ERROR if anything fails.
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

**Exact call sites:**

In `_generate_one_openai`, replace:
```python
audio_b64 = base64.b64encode(response.content).decode()
```
with:
```python
audio_b64 = base64.b64encode(_append_silence(response.content, "mp3")).decode()
```
This is inside the existing `try` block, after audio bytes are obtained. Error lines return early before this line and are not affected.

In `_generate_one_gemini`, replace:
```python
wav_bytes = _pcm_to_wav(pcm_bytes)
audio_b64 = base64.b64encode(wav_bytes).decode()
```
with:
```python
wav_bytes = _pcm_to_wav(pcm_bytes)
audio_b64 = base64.b64encode(_append_silence(wav_bytes, "wav")).decode()
```
Again inside the existing `try` block, after WAV bytes are produced.

Add `pydub` to `backend/requirements.txt`.

### Gemini file extension note

`loading_screen.dart` saves all audio with a `.mp3` extension; Gemini produces WAV bytes stored under that extension — this is pre-existing. `combined.export(buf, format="wav")` produces a valid standard WAV container. `media_kit` reads the audio container header, not the file extension, so playback works correctly from a `.mp3`-named WAV file. **Do not change the extension.**

### ffmpeg on Windows

`pydub` requires `ffmpeg` on the system PATH to decode/encode **MP3** (OpenAI path only). For **WAV** (Gemini path), pydub delegates to Python's built-in `wave` module — **no ffmpeg required**.

On Windows: install via `winget install ffmpeg` or `choco install ffmpeg`, then restart the terminal. Verify with `ffmpeg -version` before running the backend.

If `ffmpeg` is absent: `_append_silence` raises (pydub throws `CouldntDecodeError` or similar), logs at `ERROR` level for every OpenAI TTS call, and falls back to original audio bytes. Gemini calls continue to work normally. The high volume of ERROR logs makes the root cause easy to diagnose.

### Error handling

Log at `ERROR` level; return the original audio bytes unchanged. The TTS request does not fail — the user gets audio without silence rather than no audio at all.

---

## Feature 2: Delete Audio Version

### Problem

Once an audio version is generated, there is no way to delete it. Users cannot free disk space or remove failed/unwanted versions.

### Solution

Long-press on an audio version `ListTile` in `BookDetailScreen` to trigger a confirmation dialog. On confirm, delete audio files from disk and remove the DB record.

Deletion is **disabled for versions with `status == 'generating'`** — deleting mid-generation would cause `LoadingScreen` to silently re-insert the DB record after deletion (zombie record), because its `updateAudioVersionStatus` calls no-op on missing rows and the final `insertAudioVersion` re-creates the record with `status: 'ready'` pointing to a partial directory.

### Known Limitation: Concurrent Playback + Delete

If a user is actively playing an audio version in `PlayerScreen` and simultaneously deletes it from `BookDetailScreen` (e.g., using split-screen on tablet, or if router stack allows both), `media_kit` may fail on the next line load once the audio directory is deleted. The existing null-guard in `_loadAndPlayCurrentLine` (`if (version == null) return;`) handles the DB-null case on the next line, but the currently-playing file may produce a platform-dependent error when its file is deleted mid-play. This is accepted as an out-of-scope edge case — the navigation stack in normal usage requires the user to navigate back before reaching `BookDetailScreen`, making simultaneous access effectively impossible on phone/tablet in non-split-screen mode.

### Implementation

**`lib/db/database.dart`**

Add:
```dart
Future<void> deleteAudioVersion(String versionId) async {
  final db = await database;
  await db.delete('audio_versions', where: 'version_id = ?', whereArgs: [versionId]);
}
```

**`lib/screens/book_detail_screen.dart`**

`dart:io` is already imported at line 1 — no new import needed.

Convert `BookDetailScreen` from `ConsumerWidget` to `ConsumerStatefulWidget` + `ConsumerState<BookDetailScreen>`. This is needed to safely call `ref.invalidate` after an `await` — in a `ConsumerWidget`, `ref` is only valid within the synchronous `build` scope.

The three existing helper methods `_coverPlaceholder`, `_languageName`, and `_showNewLanguageSheet` **stay on the widget class** (they have no state dependencies). After conversion, `build` moves to `_BookDetailScreenState`, so all calls to these helpers inside `build` must be prefixed with `widget.`:
- `_coverPlaceholder(context)` → `widget._coverPlaceholder(context)`
- `_languageName(v.language)` → `widget._languageName(v.language)`
- `_showNewLanguageSheet(context, book)` → `widget._showNewLanguageSheet(context, book)`

This is valid Dart: `_` prefix is file-level (library-private), not class-private, so the state class can access these methods via `widget`.

The delete logic is triggered from a `GestureDetector.onLongPress` inside `build`. The callback captures `this` (the `ConsumerState`), so `mounted` and `ref` in the callback refer to the parent `ConsumerState`, not the dialog. This is the correct pattern.

Wrap **every** audio version `ListTile` uniformly in a `GestureDetector`. Use a conditional `onLongPress`:
- `status == 'generating'`: `onLongPress: null` (no-op, no gesture detected)
- all other statuses: `onLongPress: () => _confirmDelete(context, v)`

Add a method `_confirmDelete` to `_BookDetailScreenState`:

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
                            await Directory(version.audioDir).delete(recursive: true);
                          } on FileSystemException {
                            // Directory already gone — proceed to DB cleanup.
                          }
                        }
                        await AppDatabase.instance.deleteAudioVersion(version.versionId);
                        success = true;
                      } finally {
                        // Only reset loading state if still showing (i.e., not success path).
                        // On success we pop the dialog immediately below.
                        if (!success && mounted) setDialogState(() => deleting = false);
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

Key points:
- `deleting` state lives inside `StatefulBuilder` — it drives only the dialog button state.
- The `success` flag separates the success path (pop dialog) from the error path (reset button) to avoid calling `setDialogState` after `Navigator.pop` on an unmounted dialog widget.
- `Navigator.pop(dialogContext)` uses the dialog's own `BuildContext` — closes only the dialog, not the screen.
- `ref.invalidate(audioVersionsProvider(widget.bookId))` uses `widget.bookId` from `ConsumerState`.
- `mounted` checks guard against the parent `ConsumerState` being disposed before the async completes.

### Edge Cases

- **`audioDir` is empty string**: skip `Directory.delete` — version was never fully generated.
- **`FileSystemException` on delete**: caught and ignored — directory already gone; DB cleanup continues.
- **Version with `status == 'generating'`**: `onLongPress` is `null`; deletion is silently disabled.
- **Version currently playing**: not reachable simultaneously in normal navigation. If deleted while stale `PlayerScreen` is in stack, `getAudioVersion` returns `null` → `PlayerScreen` shows "Version not found" (handled at `player_screen.dart:51–52`).

---

## Out of Scope

- Configurable silence duration (600ms hardcoded).
- Deleting a book and all its versions.
- Batch delete of multiple versions.
- Fixing the Gemini `.mp3` extension mismatch.
- Preventing delete while `PlayerScreen` is actively playing (concurrent playback + delete).
