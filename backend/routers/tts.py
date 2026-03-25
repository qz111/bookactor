import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from backend.services.tts_service import generate_audio

logger = logging.getLogger(__name__)
router = APIRouter()


class TtsLine(BaseModel):
    index: int
    text: str
    voice: str


class TtsRequest(BaseModel):
    lines: list[TtsLine]
    tts_provider: str = "openai"
    openai_api_key: str = ""
    google_api_key: str = ""


@router.post("/tts")
async def tts(req: TtsRequest):
    """Generate TTS audio for all lines in parallel."""
    lines = [line.model_dump() for line in req.lines]
    try:
        return await generate_audio(
            lines=lines,
            tts_provider=req.tts_provider,
            openai_api_key=req.openai_api_key,
            google_api_key=req.google_api_key,
        )
    except Exception as exc:
        logger.exception("Error in /tts")
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}") from exc
