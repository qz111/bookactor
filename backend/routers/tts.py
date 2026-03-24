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
    openai_api_key: str


@router.post("/tts")
async def tts(req: TtsRequest):
    """Generate TTS audio for all lines in parallel."""
    lines = [line.model_dump() for line in req.lines]
    return await generate_audio(lines=lines, openai_api_key=req.openai_api_key)
