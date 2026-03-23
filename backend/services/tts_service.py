import asyncio
import base64
from openai import AsyncOpenAI
from backend.config import OPENAI_API_KEY

_tts_client = AsyncOpenAI(api_key=OPENAI_API_KEY or "dummy")


async def _generate_one(client, line: dict) -> dict:
    """Generate TTS audio for one line; returns status dict with optional audio_b64.

    On success: {"index": N, "status": "ready", "audio_b64": "<base64 mp3>"}
    On failure: {"index": N, "status": "error"}  — no audio_b64 key
    """
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


async def generate_audio(lines: list[dict]) -> list[dict]:
    """Generate TTS audio in parallel for all lines; returns results in original index order."""
    tasks = [_generate_one(_tts_client, line) for line in lines]
    results = await asyncio.gather(*tasks)
    return sorted(results, key=lambda r: r["index"])
