from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from backend.services.llm_service import generate_script

router = APIRouter()


class ScriptRequest(BaseModel):
    vlm_output: list[dict]
    language: str
    llm_provider: str


@router.post("/script")
def script(req: ScriptRequest):
    """Generate a structured audiobook script from VLM output using an LLM.

    Returns:
        {"script": {"characters": [...], "lines": [...]}}

    Raises:
        HTTPException(422): If LLM returns invalid JSON after 1 retry.
    """
    try:
        result = generate_script(
            vlm_output=req.vlm_output,
            language=req.language,
            llm_provider=req.llm_provider,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"script": result}
