import logging
import os
import sys
import traceback

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from backend.config import GOOGLE_API_KEY, OPENAI_API_KEY
from backend.routers.analyze import router as analyze_router
from backend.routers.script import router as script_router
from backend.routers.tts import router as tts_router

# Force a stderr handler so logs are visible regardless of uvicorn's log config.
_handler = logging.StreamHandler(sys.stderr)
_handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s"))
logging.root.addHandler(_handler)
logging.root.setLevel(logging.INFO)

logger = logging.getLogger(__name__)

os.environ.setdefault("GOOGLE_API_KEY", GOOGLE_API_KEY)
os.environ.setdefault("OPENAI_API_KEY", OPENAI_API_KEY)

app = FastAPI(title="BookActor Backend")


class _LogExceptionsMiddleware(BaseHTTPMiddleware):
    """Outermost middleware: catch any unhandled exception, log it, return JSON 500."""

    async def dispatch(self, request: Request, call_next):
        try:
            return await call_next(request)
        except Exception as exc:
            tb = traceback.format_exc()
            logger.error("Unhandled exception on %s %s\n%s", request.method, request.url.path, tb)
            return JSONResponse(
                status_code=500,
                content={"detail": f"{type(exc).__name__}: {exc}"},
            )


# Add error middleware first so it wraps everything (including CORS).
app.add_middleware(_LogExceptionsMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(analyze_router)
app.include_router(script_router)
app.include_router(tts_router)


@app.get("/health")
def health():
    return {"status": "ok"}
