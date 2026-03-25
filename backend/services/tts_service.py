import asyncio
import base64
import io
import logging
import wave
from openai import AsyncOpenAI
from pydub import AudioSegment

logger = logging.getLogger(__name__)

# OpenAI TTS voices
OPENAI_VOICES = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]

# Gemini TTS voices (subset of 30 available; covers a range of tones and genders)
GEMINI_VOICES = ["Aoede", "Charon", "Fenrir", "Kore", "Puck", "Zephyr", "Leda", "Orus"]


def _pcm_to_wav(pcm_bytes: bytes) -> bytes:
    """Wrap raw 24 kHz 16-bit mono PCM in a WAV container."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)  # 16-bit
        w.setframerate(24000)
        w.writeframes(pcm_bytes)
    return buf.getvalue()


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


async def _generate_one_openai(client: AsyncOpenAI, line: dict) -> dict:
    try:
        response = await client.audio.speech.create(
            model="tts-1",
            input=line["text"],
            voice=line["voice"],
            response_format="mp3",
        )
        audio_b64 = base64.b64encode(response.content).decode()
        return {"index": line["index"], "status": "ready", "audio_b64": audio_b64}
    except Exception:
        return {"index": line["index"], "status": "error"}


async def _generate_one_gemini(client, line: dict) -> dict:
    try:
        from google.genai import types

        response = await asyncio.to_thread(
            client.models.generate_content,
            model="gemini-2.5-pro-preview-tts",
            contents=line["text"],
            config=types.GenerateContentConfig(
                response_modalities=["AUDIO"],
                speech_config=types.SpeechConfig(
                    voice_config=types.VoiceConfig(
                        prebuilt_voice_config=types.PrebuiltVoiceConfig(
                            voice_name=line["voice"]
                        )
                    )
                ),
            ),
        )
        pcm_bytes = response.candidates[0].content.parts[0].inline_data.data
        wav_bytes = _pcm_to_wav(pcm_bytes)
        audio_b64 = base64.b64encode(wav_bytes).decode()
        return {"index": line["index"], "status": "ready", "audio_b64": audio_b64}
    except Exception:
        return {"index": line["index"], "status": "error"}


async def _generate_gemini_throttled(client, lines: list[dict], rpm: int = 10) -> list[dict]:
    """Generate Gemini TTS one line at a time, respecting the RPM limit."""
    min_interval = 60.0 / rpm  # 6 s between request starts at 10 RPM
    results = []
    last_start: float | None = None

    for line in lines:
        if last_start is not None:
            elapsed = asyncio.get_event_loop().time() - last_start
            wait = min_interval - elapsed
            if wait > 0:
                await asyncio.sleep(wait)

        last_start = asyncio.get_event_loop().time()
        result = await _generate_one_gemini(client, line)
        results.append(result)

    return results


async def generate_audio(
    lines: list[dict],
    tts_provider: str,
    openai_api_key: str,
    google_api_key: str,
) -> list[dict]:
    """Generate TTS audio for all lines; returns results sorted by index."""
    if tts_provider == "gemini":
        from google import genai
        client = genai.Client(api_key=google_api_key)
        results = await _generate_gemini_throttled(client, lines)
    else:
        client = AsyncOpenAI(api_key=openai_api_key)
        tasks = [_generate_one_openai(client, line) for line in lines]
        results = list(await asyncio.gather(*tasks))

    return sorted(results, key=lambda r: r["index"])
