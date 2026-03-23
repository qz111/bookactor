from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from backend.config import GOOGLE_API_KEY, OPENAI_API_KEY
from backend.routers.analyze import router as analyze_router
from backend.routers.script import router as script_router
from backend.routers.tts import router as tts_router
import os

os.environ.setdefault("GOOGLE_API_KEY", GOOGLE_API_KEY)
os.environ.setdefault("OPENAI_API_KEY", OPENAI_API_KEY)

app = FastAPI(title="BookActor Backend")
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
