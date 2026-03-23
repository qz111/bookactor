from fastapi import FastAPI
from backend.routers.analyze import router as analyze_router

app = FastAPI(title="BookActor Backend")
app.include_router(analyze_router)

@app.get("/health")
def health():
    return {"status": "ok"}
