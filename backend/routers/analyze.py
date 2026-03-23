import asyncio
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from typing import Annotated
from backend.services.vlm_service import analyze_pages

router = APIRouter()


@router.post("/analyze")
async def analyze(
    images: Annotated[list[UploadFile], File()],
    vlm_provider: Annotated[str, Form()],
):
    """Analyze book page images using a Vision Language Model.

    Returns:
        {"pages": [{"page": int, "text": str}, ...]}

    Raises:
        HTTPException(422): If VLM returns invalid JSON or unknown provider.
    """
    image_bytes_list = [await img.read() for img in images]
    try:
        pages = await asyncio.to_thread(
            analyze_pages,
            image_bytes_list=image_bytes_list,
            vlm_provider=vlm_provider,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"pages": pages}
