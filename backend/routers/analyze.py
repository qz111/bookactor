import asyncio
import logging
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from typing import Annotated
from backend.services.vlm_service import analyze_pages

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/analyze")
async def analyze(
    images: Annotated[list[UploadFile], File()],
    vlm_provider: Annotated[str, Form()],
    processing_mode: Annotated[str, Form()],
    openai_api_key: Annotated[str, Form()],
    google_api_key: Annotated[str, Form()],
):
    """Analyze book page images using a Vision Language Model."""
    image_bytes_list = [await img.read() for img in images]
    try:
        pages = await asyncio.to_thread(
            analyze_pages,
            image_bytes_list=image_bytes_list,
            vlm_provider=vlm_provider,
            processing_mode=processing_mode,
            openai_api_key=openai_api_key,
            google_api_key=google_api_key,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Error in /analyze")
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}") from exc
    return {"pages": pages}
