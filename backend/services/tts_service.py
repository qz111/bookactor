import asyncio
import base64
from openai import AsyncOpenAI


async def _generate_one(client: AsyncOpenAI, line: dict) -> dict:
    """Generate TTS audio for one line; returns status dict with optional audio_b64."""
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


async def generate_audio(lines: list[dict], openai_api_key: str) -> list[dict]:
    """Generate TTS audio in parallel for all lines; returns results in original index order."""
    client = AsyncOpenAI(api_key=openai_api_key)
    tasks = [_generate_one(client, line) for line in lines]
    results = await asyncio.gather(*tasks)
    return sorted(results, key=lambda r: r["index"])
