from fastapi import FastAPI

app = FastAPI(title="BookActor Backend")

@app.get("/health")
def health():
    return {"status": "ok"}
