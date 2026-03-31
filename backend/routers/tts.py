import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from backend.services.tts_service import generate_audio, design_voices

logger = logging.getLogger(__name__)
router = APIRouter()


class TtsChunk(BaseModel):
    index: int
    text: str
    voice_map: dict[str, str]  # {"Narrator": "Aoede", "Bear": "Charon"}


class TtsRequest(BaseModel):
    chunks: list[TtsChunk]
    tts_provider: str = "openai"
    openai_api_key: str = ""
    google_api_key: str = ""
    qwen_api_key: str = ""
    qwen_workspace_id: str = ""


class VoiceDesignCharacter(BaseModel):
    name: str
    voice_prompt: str
    voice_id: str | None = None


class VoiceDesignRequest(BaseModel):
    characters: list[VoiceDesignCharacter]
    language: str
    qwen_api_key: str


class VoiceDesignResponse(BaseModel):
    characters: list[VoiceDesignCharacter]


@router.post("/tts/design-voices", response_model=VoiceDesignResponse)
async def tts_design_voices(req: VoiceDesignRequest):
    """Create custom voice IDs for Qwen VD characters."""
    chars = [c.model_dump() for c in req.characters]
    try:
        updated = await design_voices(
            characters=chars,
            language=req.language,
            qwen_api_key=req.qwen_api_key,
        )
        return VoiceDesignResponse(characters=updated)
    except Exception as exc:
        logger.exception("Error in /tts/design-voices")
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}") from exc


@router.post("/tts")
async def tts(req: TtsRequest):
    """Generate TTS audio for all chunks."""
    chunks = [chunk.model_dump() for chunk in req.chunks]
    try:
        return await generate_audio(
            chunks=chunks,
            tts_provider=req.tts_provider,
            openai_api_key=req.openai_api_key,
            google_api_key=req.google_api_key,
            qwen_api_key=req.qwen_api_key,
            qwen_workspace_id=req.qwen_workspace_id,
        )
    except Exception as exc:
        logger.exception("Error in /tts")
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}") from exc
