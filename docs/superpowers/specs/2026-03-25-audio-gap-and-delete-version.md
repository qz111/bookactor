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

Append 600ms of silence to each audio chunk in `backend/services/tts_service.py` at generation time. The silence is baked into each MP3/WAV file permanently. No Flutter or API changes required.

### Implementation

**File:** `backend/services/tts_service.py`

Add a helper `_append_silence(audio_bytes: bytes, fmt: str, duration_ms: int = 600) -> bytes`:
- For `fmt="mp3"`: use `pydub.AudioSegment` to decode the MP3, append `AudioSegment.silent(duration=duration_ms)`, and export back to MP3 bytes.
- For `fmt="wav"`: parse the WAV header to get sample rate, channels, and sample width; compute silent frame count; append zeros to the PCM data; re-wrap in a WAV container.

Call `_append_silence` in:
- `_generate_one_openai`: after receiving `response.content` (MP3 bytes), before base64-encoding.
- `_generate_one_gemini`: after `_pcm_to_wav(pcm_bytes)` produces WAV bytes, before base64-encoding.

**Dependency:** Add `pydub` to `backend/requirements.txt`.

### Constraints

- `pydub` requires `ffmpeg` available on the system PATH for MP3 decode/encode. The app already uses audio processing; this is an acceptable dependency.
- Duration is hardcoded at 600ms. No user-facing setting is needed.
- Error handling: if silence append fails, fall back to returning the original audio bytes (log the error, don't fail the whole TTS request).

---

## Feature 2: Delete Audio Version

### Problem

Once an audio version is generated, there is no way to delete it. Users cannot free disk space or remove failed/unwanted versions.

### Solution

Long-press on an audio version `ListTile` in `BookDetailScreen` to trigger a confirmation dialog. On confirm, delete audio files from disk and remove the DB record.

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
- Wrap each audio version `ListTile` in a `GestureDetector(onLongPress: ...)`.
- On long press, show `AlertDialog` with title "Delete audio version?", body "This will permanently delete all audio files. This cannot be undone.", and Cancel / Delete buttons.
- On Delete confirmed:
  1. `Directory(version.audioDir).delete(recursive: true)` — catches `FileSystemException` silently if dir doesn't exist.
  2. `AppDatabase.instance.deleteAudioVersion(version.versionId)`
  3. `ref.invalidate(audioVersionsProvider(bookId))` to refresh the list.

### Edge Cases

- **audioDir is empty string**: skip file deletion if `version.audioDir.isEmpty`.
- **Version currently generating**: allow deletion anyway; the generation in `LoadingScreen` will encounter a missing DB row and should handle it gracefully (already errors out on missing version).
- **Version currently playing**: not applicable — PlayerScreen is on a different route and the user must navigate back to reach BookDetailScreen.

---

## Out of Scope

- Configurable silence duration (hardcoded 600ms is sufficient).
- Deleting a book (only audio versions are deleted here).
- Batch delete of multiple versions.
