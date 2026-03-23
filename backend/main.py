from fastapi import FastAPI
from backend.routers.analyze import router as analyze_router
from backend.routers.script import router as script_router

app = FastAPI(title="BookActor Backend")
app.include_router(analyze_router)
app.include_router(script_router)

@app.get("/health")
def health():
    return {"status": "ok"}
