from fastapi import APIRouter
from pydantic import BaseModel
from backend.services.tts_service import generate_audio

router = APIRouter()


class TtsLine(BaseModel):
    index: int
    text: str
    voice: str


class TtsRequest(BaseModel):
    lines: list[TtsLine]


@router.post("/tts")
async def tts(req: TtsRequest):
    """Generate TTS audio for all lines in parallel.

    Returns:
        List of results: [{"index": int, "status": "ready", "audio_b64": str}, ...]
        Error lines: {"index": int, "status": "error"}  — no audio_b64
    """
    lines = [line.model_dump() for line in req.lines]
    return await generate_audio(lines)
