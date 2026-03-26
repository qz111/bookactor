import asyncio
import base64
import io
import logging
import wave
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

# Gender classification for Gemini voices (used when collapsing 3+ speakers to 2).
_FEMALE_VOICES = {"Aoede", "Kore", "Zephyr", "Leda"}


def _collapse_to_two_speakers(text: str, voice_map: dict[str, str]) -> tuple[str, dict[str, str]]:
    """Collapse 3+ speakers to exactly 2 for Gemini multi-speaker API.

    Groups characters by voice gender: narrator's gender group vs contrasting group.
    All same-gender-as-narrator characters are merged under the narrator's speaker
    label. All contrasting-gender characters share the first contrasting speaker label.
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
        # All same gender — treat first non-narrator as the contrast speaker.
        for name, voice in voice_map.items():
            if name != narrator_name:
                contrast_group.append(name)
                contrast_voice = voice
                break
        same_group = [narrator_name]

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
) -> list[dict]:
    """Generate TTS audio for all chunks; returns results sorted by index."""
    if tts_provider == "gemini":
        client = genai.Client(api_key=google_api_key)
        results = await _generate_gemini_throttled(client, chunks)
    else:
        client = AsyncOpenAI(api_key=openai_api_key)
        tasks = [_generate_chunk_openai(client, chunk) for chunk in chunks]
        results = list(await asyncio.gather(*tasks))
    return sorted(results, key=lambda r: r["index"])
