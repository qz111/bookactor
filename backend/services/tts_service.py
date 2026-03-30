import asyncio
import base64
import io
import logging
import wave
import httpx
from google import genai
from google.genai import types
from openai import AsyncOpenAI
from pydub import AudioSegment

logger = logging.getLogger(__name__)

# OpenAI TTS voices
OPENAI_VOICES = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]

# Gemini TTS voices (subset of 30 available; covers a range of tones and genders)
GEMINI_VOICES = ["Aoede", "Charon", "Fenrir", "Kore", "Puck", "Zephyr", "Leda", "Orus"]

# Fallback map for scripts generated with OpenAI voices but played via Gemini TTS.
_OPENAI_TO_GEMINI = {
    "alloy": "Aoede", "echo": "Charon", "fable": "Fenrir",
    "onyx": "Kore", "nova": "Puck", "shimmer": "Zephyr",
}

# Gender classification for Gemini voices.
_FEMALE_VOICES = {"Aoede", "Kore", "Zephyr", "Leda"}
_MALE_VOICES = {"Charon", "Fenrir", "Puck", "Orus"}
# Default contrasting voice when no naturally opposing voice exists.
_DEFAULT_FEMALE = "Aoede"
_DEFAULT_MALE = "Charon"


def _contrasting_voice(narrator_voice: str) -> str:
    """Return a voice of the opposite gender to narrator_voice."""
    if narrator_voice in _FEMALE_VOICES:
        return _DEFAULT_MALE
    return _DEFAULT_FEMALE


def _collapse_to_two_speakers(text: str, voice_map: dict[str, str]) -> tuple[str, dict[str, str]]:
    """Collapse 3+ speakers to exactly 2 for Gemini multi-speaker API.

    Groups by voice gender: same-gender-as-narrator speakers are merged under the
    narrator label. Contrasting-gender speakers share the first contrasting label.
    When all speakers share the narrator's gender, a default opposite-gender voice
    is assigned to the contrast speaker so the two voices are always distinct.
    Narrator's voice and name are never changed.
    """
    narrator_name = next(
        (name for name in voice_map if name.lower() == "narrator"),
        list(voice_map.keys())[0],
    )
    narrator_voice = voice_map[narrator_name]
    narrator_is_female = narrator_voice in _FEMALE_VOICES

    same_group: list[str] = [narrator_name]
    contrast_group: list[str] = []
    contrast_voice: str | None = None

    for name, voice in voice_map.items():
        if name == narrator_name:
            continue
        if (voice in _FEMALE_VOICES) == narrator_is_female:
            same_group.append(name)
        else:
            contrast_group.append(name)
            if contrast_voice is None:
                contrast_voice = voice

    if not contrast_group:
        # All same gender — pick first non-narrator as contrast speaker using their
        # own assigned voice (a different same-gender voice is still distinguishable).
        for name, voice in voice_map.items():
            if name != narrator_name:
                contrast_group.append(name)
                contrast_voice = voice
                break
        same_group = [narrator_name]
        # Safety: if contrast voice happens to equal narrator's voice, pick any
        # other voice of the same gender so Gemini can still differentiate speakers.
        if contrast_voice == narrator_voice:
            same_gender_pool = list(_FEMALE_VOICES if narrator_is_female else _MALE_VOICES)
            for v in same_gender_pool:
                if v != narrator_voice:
                    contrast_voice = v
                    break

    contrast_name = contrast_group[0]
    new_voice_map = {narrator_name: narrator_voice, contrast_name: contrast_voice}

    lines = []
    for line in text.strip().split("\n"):
        if ": " not in line:
            lines.append(line)
            continue
        name, utterance = line.split(": ", 1)
        name = name.strip()
        if name in same_group and name != narrator_name:
            lines.append(f"{narrator_name}: {utterance}")
        elif name not in new_voice_map:
            lines.append(f"{contrast_name}: {utterance}")
        else:
            lines.append(line)

    return "\n".join(lines), new_voice_map


def _pcm_to_wav(pcm_bytes: bytes) -> bytes:
    """Wrap raw 24 kHz 16-bit mono PCM in a WAV container."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)  # 16-bit
        w.setframerate(24000)
        w.writeframes(pcm_bytes)
    return buf.getvalue()


def _wav_duration_ms(wav_bytes: bytes) -> int:
    """Return duration in milliseconds of a WAV file."""
    with wave.open(io.BytesIO(wav_bytes)) as w:
        return int(w.getnframes() / w.getframerate() * 1000)


def _parse_chunk_segments(text: str, voice_map: dict[str, str]) -> list[dict]:
    """Parse 'Character: utterance\\n' text into [{text, voice}] segments."""
    segments = []
    fallback_voice = list(voice_map.values())[0] if voice_map else "alloy"
    for line in text.strip().split("\n"):
        if ": " not in line:
            continue
        name, utterance = line.split(": ", 1)
        voice = voice_map.get(name.strip(), fallback_voice)
        segments.append({"text": utterance.strip(), "voice": voice})
    return segments


def _merge_qwen_segments(segments: list[dict]) -> list[dict]:
    """Merge consecutive same-voice segments that fit within 300 chars (incl. separator)."""
    if not segments:
        return []
    merged = [segments[0].copy()]
    for seg in segments[1:]:
        last = merged[-1]
        if seg["voice"] == last["voice"] and len(last["text"]) + 1 + len(seg["text"]) <= 300:
            last["text"] = last["text"] + "，" + seg["text"]
        else:
            merged.append(seg.copy())
    return merged


def _split_qwen_segment(seg: dict) -> list[dict]:
    """Split a segment exceeding 300 chars at sentence boundaries."""
    text, voice = seg["text"], seg["voice"]
    if len(text) <= 300:
        return [seg.copy()]
    results = []
    while len(text) > 300:
        window = text[:300]
        cut = max(window.rfind("。"), window.rfind("！"), window.rfind("？"))
        if cut == -1:
            cut = window.rfind("，")
        if cut == -1:
            cut = 299  # hard split
        results.append({"text": text[:cut + 1], "voice": voice})
        text = text[cut + 1:]
    if text:
        results.append({"text": text, "voice": voice})
    return results


def _flatten_split_qwen_segments(segments: list[dict]) -> list[dict]:
    """Apply split to all segments, returning a flat list."""
    return [piece for seg in segments for piece in _split_qwen_segment(seg)]


_DASHSCOPE_TTS_URL = (
    "https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
)


async def _call_qwen_segment(client: httpx.AsyncClient, seg: dict) -> bytes | None:
    """Call DashScope native API for a single segment. Returns WAV bytes or None on error."""
    try:
        payload = {
            "model": "qwen3-tts-instruct-flash",
            "input": {
                "text": seg["text"],
                "voice": seg["voice"],
            },
        }
        resp = await client.post(_DASHSCOPE_TTS_URL, json=payload)
        resp.raise_for_status()
        audio_url = resp.json()["output"]["audio"]["url"]
        audio_resp = await client.get(audio_url)
        audio_resp.raise_for_status()
        if not audio_resp.content:
            raise ValueError("Empty audio response from DashScope")
        return audio_resp.content
    except Exception:
        logger.exception("Qwen TTS segment call failed")
        return None


async def _generate_qwen_throttled(client, chunks: list[dict], rpm: int = 180) -> list[dict]:
    """Generate Qwen TTS across all chunks, throttling between each API call at rpm."""
    min_interval = 60.0 / rpm
    results = []
    last_start: float | None = None

    for chunk in chunks:
        segments = _parse_chunk_segments(chunk["text"], chunk["voice_map"])
        segments = _merge_qwen_segments(segments)
        segments = _flatten_split_qwen_segments(segments)

        wav_parts = []
        chunk_error = False
        for seg in segments:
            if last_start is not None:
                elapsed = asyncio.get_event_loop().time() - last_start
                wait = min_interval - elapsed
                if wait > 0:
                    await asyncio.sleep(wait)
            last_start = asyncio.get_event_loop().time()

            part = await _call_qwen_segment(client, seg)
            if part is None:
                chunk_error = True
                break
            wav_parts.append(part)

        if chunk_error or not wav_parts:
            results.append({"index": chunk["index"], "status": "error", "duration_ms": 0})
        else:
            combined = AudioSegment.from_wav(io.BytesIO(wav_parts[0]))
            for part in wav_parts[1:]:
                combined += AudioSegment.from_wav(io.BytesIO(part))
            buf = io.BytesIO()
            combined.export(buf, format="wav")
            wav_bytes = buf.getvalue()
            wav_with_silence = _append_silence(wav_bytes, "wav")
            duration_ms = _wav_duration_ms(wav_with_silence)
            results.append({
                "index": chunk["index"],
                "status": "ready",
                "audio_b64": base64.b64encode(wav_with_silence).decode(),
                "duration_ms": duration_ms,
            })

    return results


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


async def _generate_chunk_openai(client: AsyncOpenAI, chunk: dict) -> dict:
    """Generate audio for a chunk using OpenAI TTS; segments concatenated as WAV."""
    try:
        segments = _parse_chunk_segments(chunk["text"], chunk["voice_map"])
        if not segments:
            raise ValueError("No segments parsed from chunk text")

        wav_parts = []
        for seg in segments:
            response = await client.audio.speech.create(
                model="tts-1",
                input=seg["text"],
                voice=seg["voice"],
                response_format="wav",
            )
            wav_parts.append(response.content)

        combined = AudioSegment.from_wav(io.BytesIO(wav_parts[0]))
        for part in wav_parts[1:]:
            combined += AudioSegment.from_wav(io.BytesIO(part))

        buf = io.BytesIO()
        combined.export(buf, format="wav")
        wav_bytes = buf.getvalue()
        wav_with_silence = _append_silence(wav_bytes, "wav")
        duration_ms = _wav_duration_ms(wav_with_silence)
        audio_b64 = base64.b64encode(wav_with_silence).decode()
        return {"index": chunk["index"], "status": "ready", "audio_b64": audio_b64, "duration_ms": duration_ms}
    except Exception:
        logger.exception("OpenAI TTS failed for chunk %d", chunk["index"])
        return {"index": chunk["index"], "status": "error", "duration_ms": 0}


async def _generate_chunk_gemini(client, chunk: dict) -> dict:
    """Generate audio for a chunk using Gemini TTS.

    - 1 speaker  → single-speaker VoiceConfig
    - 2 speakers → MultiSpeakerVoiceConfig as-is
    - 3+ speakers → collapse to 2 by gender grouping, then MultiSpeakerVoiceConfig
    """
    try:
        voice_map = {
            name: _OPENAI_TO_GEMINI.get(v.lower(), v)
            for name, v in chunk["voice_map"].items()
        }

        text = chunk["text"]
        if len(voice_map) > 2:
            text, voice_map = _collapse_to_two_speakers(text, voice_map)

        # For 2-speaker mode: ensure the two voices are distinct.
        # If the LLM assigned the same voice to both, give the non-narrator a
        # different voice from the same gender pool (keeps tonal consistency).
        if len(voice_map) == 2:
            names = list(voice_map.keys())
            if voice_map[names[0]] == voice_map[names[1]]:
                narrator_name = next(
                    (n for n in names if n.lower() == "narrator"), names[0]
                )
                other_name = names[1] if names[0] == narrator_name else names[0]
                nv = voice_map[narrator_name]
                same_pool = list(_FEMALE_VOICES if nv in _FEMALE_VOICES else _MALE_VOICES)
                candidate = next((v for v in same_pool if v != nv), _contrasting_voice(nv))
                voice_map[other_name] = candidate

        if len(voice_map) >= 2:
            speech_config = types.SpeechConfig(
                multi_speaker_voice_config=types.MultiSpeakerVoiceConfig(
                    speaker_voice_configs=[
                        types.SpeakerVoiceConfig(
                            speaker=name,
                            voice_config=types.VoiceConfig(
                                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice)
                            ),
                        )
                        for name, voice in voice_map.items()
                    ]
                )
            )
        else:
            voice = list(voice_map.values())[0]
            speech_config = types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice)
                )
            )

        response = await asyncio.to_thread(
            client.models.generate_content,
            model="gemini-2.5-pro-preview-tts",
            contents=text,
            config=types.GenerateContentConfig(
                response_modalities=["AUDIO"],
                speech_config=speech_config,
            ),
        )
        candidate = response.candidates[0]
        if candidate.content is None:
            finish = getattr(candidate, "finish_reason", "unknown")
            raise ValueError(f"Gemini returned no content (finish_reason={finish})")
        pcm_bytes = candidate.content.parts[0].inline_data.data
        wav_bytes = _pcm_to_wav(pcm_bytes)
        wav_with_silence = _append_silence(wav_bytes, "wav")
        duration_ms = _wav_duration_ms(wav_with_silence)
        audio_b64 = base64.b64encode(wav_with_silence).decode()
        return {"index": chunk["index"], "status": "ready", "audio_b64": audio_b64, "duration_ms": duration_ms}
    except Exception:
        logger.exception("Gemini TTS failed for chunk %d", chunk["index"])
        return {"index": chunk["index"], "status": "error", "duration_ms": 0}


async def _generate_gemini_throttled(client, chunks: list[dict], rpm: int = 10) -> list[dict]:
    """Generate Gemini TTS one chunk at a time, respecting the RPM limit."""
    min_interval = 60.0 / rpm
    results = []
    last_start: float | None = None

    for chunk in chunks:
        if last_start is not None:
            elapsed = asyncio.get_event_loop().time() - last_start
            wait = min_interval - elapsed
            if wait > 0:
                await asyncio.sleep(wait)
        last_start = asyncio.get_event_loop().time()
        result = await _generate_chunk_gemini(client, chunk)
        results.append(result)

    return results


async def generate_audio(
    chunks: list[dict],
    tts_provider: str,
    openai_api_key: str,
    google_api_key: str,
    qwen_api_key: str = "",
    qwen_workspace_id: str = "",
) -> list[dict]:
    """Generate TTS audio for all chunks; returns results sorted by index."""
    if tts_provider == "gemini":
        client = genai.Client(api_key=google_api_key)
        results = await _generate_gemini_throttled(client, chunks)
    elif tts_provider == "qwen":
        async with httpx.AsyncClient(
            headers={"Authorization": f"Bearer {qwen_api_key}"},
            timeout=httpx.Timeout(60.0),
        ) as client:
            results = await _generate_qwen_throttled(client, chunks)
    else:
        client = AsyncOpenAI(api_key=openai_api_key)
        tasks = [_generate_chunk_openai(client, chunk) for chunk in chunks]
        results = list(await asyncio.gather(*tasks))
    return sorted(results, key=lambda r: r["index"])
