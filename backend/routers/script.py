import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from backend.services.llm_service import generate_script

logger = logging.getLogger(__name__)
router = APIRouter()


class ScriptRequest(BaseModel):
    vlm_output: list[dict]
    language: str
    llm_provider: str
    tts_provider: str = "openai"
    openai_api_key: str
    google_api_key: str


@router.post("/script")
def script(req: ScriptRequest):
    """Generate a structured audiobook script from VLM output using an LLM."""
    try:
        result = generate_script(
            vlm_output=req.vlm_output,
            language=req.language,
            llm_provider=req.llm_provider,
            tts_provider=req.tts_provider,
            openai_api_key=req.openai_api_key,
            google_api_key=req.google_api_key,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Error in /script")
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}") from exc
    return {"script": result}
