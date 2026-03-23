# Phase 3a: FastAPI Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a stateless FastAPI backend proxy that exposes three endpoints (`/analyze`, `/script`, `/tts`) routing AI calls through LiteLLM (VLM/LLM) and the OpenAI SDK (TTS), with API keys stored only on the server.

**Architecture:** Three thin endpoint modules in `backend/routers/`, each delegating to a service module in `backend/services/`. The app entrypoint (`backend/main.py`) wires up routers and shared config. Tests mock all AI provider calls so the suite runs without any API keys.

**Tech Stack:** Python 3.11+, FastAPI, Uvicorn, LiteLLM, OpenAI SDK (`openai`), pytest, pytest-asyncio, httpx (async test client), python-multipart (multipart form parsing), python-dotenv

---

## File Structure

```
backend/
  __init__.py                # empty
  main.py                    # FastAPI app, includes routers, health endpoint
  config.py                  # Reads env vars (API keys)
  routers/
    __init__.py              # empty
    analyze.py               # POST /analyze — multipart images → VLM → pages JSON
    script.py                # POST /script  — vlm_output + language → LLM → script JSON
    tts.py                   # POST /tts     — lines array → OpenAI TTS → base64 mp3s
  services/
    __init__.py              # empty
    vlm_service.py           # Calls LiteLLM completion with vision input
    llm_service.py           # Calls LiteLLM completion for script generation; 1 auto-retry on bad JSON
    tts_service.py           # Calls openai.audio.speech.create per line; parallel via asyncio.gather
  requirements.txt           # fastapi uvicorn litellm openai python-multipart python-dotenv
tests/
  __init__.py                # empty — ensures pytest discovers tests/services/ subdirectory
  conftest.py                # Shared fixtures: TestClient
  test_health.py             # GET /health
  test_analyze.py            # /analyze endpoint tests (mock vlm_service)
  test_script.py             # /script endpoint tests (mock llm_service)
  test_tts.py                # /tts endpoint tests (mock tts_service)
  services/
    __init__.py              # empty
    test_vlm_service.py      # Unit tests for vlm_service (mock litellm.completion)
    test_llm_service.py      # Unit tests for llm_service including retry logic
    test_tts_service.py      # Unit tests for tts_service (mock openai client)
.env.example                 # OPENAI_API_KEY=sk-... GOOGLE_API_KEY=... (no real keys)
```

---

### Task 1: Project scaffold and config

**Files:**
- Create: `backend/__init__.py`
- Create: `backend/main.py`
- Create: `backend/config.py`
- Create: `backend/requirements.txt`
- Create: `tests/__init__.py`
- Create: `tests/conftest.py`
- Create: `tests/test_health.py`
- Create: `.env.example`

- [ ] **Step 1: Install dependencies**

```bash
cd D:/developer_tools/bookactor/.worktrees/phase3-fastapi-backend
pip install fastapi uvicorn litellm openai python-multipart python-dotenv pytest pytest-asyncio httpx
```

Expected: exit 0

- [ ] **Step 2: Write the failing test**

Create `tests/test_health.py`:

```python
def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

Create `tests/conftest.py`:

```python
import pytest
from fastapi.testclient import TestClient

@pytest.fixture
def client():
    from backend.main import app
    return TestClient(app)
```

Create empty files: `tests/__init__.py`

- [ ] **Step 3: Run test to verify it fails**

```bash
pytest tests/test_health.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'backend'`

- [ ] **Step 4: Create `backend/requirements.txt`**

```
fastapi
uvicorn[standard]
litellm
openai
python-multipart
python-dotenv
```

- [ ] **Step 5: Create `backend/__init__.py`** (empty)

- [ ] **Step 6: Create `backend/config.py`**

```python
import os
from dotenv import load_dotenv

load_dotenv()

OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
GOOGLE_API_KEY: str = os.getenv("GOOGLE_API_KEY", "")
```

- [ ] **Step 7: Create `backend/main.py`**

```python
from fastapi import FastAPI

app = FastAPI(title="BookActor Backend")

@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 8: Create `.env.example`**

```
OPENAI_API_KEY=sk-...
GOOGLE_API_KEY=your-google-api-key
```

- [ ] **Step 9: Run test to verify it passes**

```bash
pytest tests/test_health.py -v
```

Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add backend/__init__.py backend/main.py backend/config.py backend/requirements.txt tests/__init__.py tests/conftest.py tests/test_health.py .env.example
git commit -m "feat: scaffold FastAPI backend with health endpoint"
```

---

### Task 2: VLM service unit

**Files:**
- Create: `backend/services/__init__.py`
- Create: `backend/services/vlm_service.py`
- Create: `tests/services/__init__.py`
- Create: `tests/services/test_vlm_service.py`

- [ ] **Step 1: Write the failing tests**

Create `tests/services/test_vlm_service.py`:

```python
import pytest
from unittest.mock import patch, MagicMock

SAMPLE_PAGES_RESPONSE = '{"pages": [{"page": 1, "text": "Once upon a time"}, {"page": 2, "text": "The end"}]}'

def _make_completion_mock(content: str):
    mock = MagicMock()
    mock.choices[0].message.content = content
    return mock

@patch("litellm.completion")
def test_analyze_gemini_returns_pages(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    result = analyze_pages(
        image_bytes_list=[b"fakejpeg"],
        vlm_provider="gemini",
    )
    assert result == [{"page": 1, "text": "Once upon a time"}, {"page": 2, "text": "The end"}]
    mock_completion.assert_called_once()
    call_kwargs = mock_completion.call_args.kwargs
    assert call_kwargs["model"].startswith("gemini")

@patch("litellm.completion")
def test_analyze_gpt4o_uses_correct_model(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(image_bytes_list=[b"fakejpeg"], vlm_provider="gpt4o")
    call_kwargs = mock_completion.call_args.kwargs
    assert "gpt-4o" in call_kwargs["model"]

@patch("litellm.completion")
def test_analyze_encodes_images_as_base64(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(image_bytes_list=[b"fakejpeg", b"fakejpeg2"], vlm_provider="gemini")
    call_kwargs = mock_completion.call_args.kwargs
    messages = call_kwargs["messages"]
    image_items = [
        c for c in messages[-1]["content"]
        if isinstance(c, dict) and c.get("type") == "image_url"
    ]
    assert len(image_items) == 2

@patch("litellm.completion")
def test_analyze_raises_on_invalid_json(mock_completion):
    mock_completion.return_value = _make_completion_mock("not json at all")
    from backend.services.vlm_service import analyze_pages
    with pytest.raises(ValueError, match="VLM returned invalid JSON"):
        analyze_pages(image_bytes_list=[b"fakejpeg"], vlm_provider="gemini")

@patch("litellm.completion")
def test_analyze_raises_on_unknown_provider(mock_completion):
    from backend.services.vlm_service import analyze_pages
    with pytest.raises(ValueError, match="Unknown vlm_provider"):
        analyze_pages(image_bytes_list=[b"fakejpeg"], vlm_provider="unknown_provider")
    mock_completion.assert_not_called()
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
pytest tests/services/test_vlm_service.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'backend.services'`

- [ ] **Step 3: Create empty `__init__.py` files** (must be done before the service implementation)

```bash
mkdir -p backend/services tests/services
touch backend/services/__init__.py tests/services/__init__.py
```

- [ ] **Step 4: Implement `backend/services/vlm_service.py`**

```python
import base64
import json
import litellm

_VLM_MODELS = {
    "gemini": "gemini/gemini-1.5-pro-latest",
    "gpt4o": "gpt-4o",
}

_SYSTEM_PROMPT = (
    "You are a children's book reader. Analyse every page image provided and "
    "return ONLY a JSON object with this exact structure, no markdown fences:\n"
    '{"pages": [{"page": <1-based int>, "text": "<all text and story from that page>"}]}'
)


def analyze_pages(image_bytes_list: list[bytes], vlm_provider: str) -> list[dict]:
    """Call VLM with page images; return list of {page, text} dicts."""
    model = _VLM_MODELS.get(vlm_provider)
    if model is None:
        raise ValueError(f"Unknown vlm_provider: {vlm_provider!r}")

    image_content = []
    for img_bytes in image_bytes_list:
        b64 = base64.b64encode(img_bytes).decode()
        image_content.append({
            "type": "image_url",
            "image_url": {"url": f"data:image/jpeg;base64,{b64}"},
        })
    image_content.append({"type": "text", "text": "Extract the story text from every page."})

    response = litellm.completion(
        model=model,
        messages=[
            {"role": "system", "content": _SYSTEM_PROMPT},
            {"role": "user", "content": image_content},
        ],
    )
    raw = response.choices[0].message.content
    try:
        data = json.loads(raw)
        return data["pages"]
    except (json.JSONDecodeError, KeyError) as exc:
        raise ValueError(f"VLM returned invalid JSON: {raw!r}") from exc
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
pytest tests/services/test_vlm_service.py -v
```

Expected: 5 PASS

- [ ] **Step 6: Commit**

```bash
git add backend/services/ tests/services/
git commit -m "feat: add VLM service with LiteLLM integration"
```

---

### Task 3: LLM service unit (with retry logic)

**Files:**
- Create: `backend/services/llm_service.py`
- Create: `tests/services/test_llm_service.py`

- [ ] **Step 1: Write the failing tests**

Create `tests/services/test_llm_service.py`:

```python
import pytest
from unittest.mock import patch, MagicMock

VALID_SCRIPT_JSON = """{
  "characters": [{"name": "Narrator", "voice": "alloy"}],
  "lines": [{"index": 0, "character": "Narrator", "text": "Once upon a time.", "page": 1, "status": "pending"}]
}"""

def _make_completion_mock(content: str):
    mock = MagicMock()
    mock.choices[0].message.content = content
    return mock

@patch("litellm.completion")
def test_generate_script_returns_parsed_dict(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    result = generate_script(
        vlm_output=[{"page": 1, "text": "Once upon a time."}],
        language="en",
        llm_provider="gpt4o",
    )
    assert "characters" in result
    assert "lines" in result
    assert result["lines"][0]["status"] == "pending"

@patch("litellm.completion")
def test_generate_script_uses_gpt4o_model(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    generate_script(vlm_output=[], language="en", llm_provider="gpt4o")
    assert "gpt-4o" in mock_completion.call_args.kwargs["model"]

@patch("litellm.completion")
def test_generate_script_uses_gemini_model(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    generate_script(vlm_output=[], language="zh", llm_provider="gemini")
    assert "gemini" in mock_completion.call_args.kwargs["model"]

@patch("litellm.completion")
def test_generate_script_retries_once_on_bad_json(mock_completion):
    """First call returns invalid JSON; second call (stricter prompt) returns valid JSON."""
    mock_completion.side_effect = [
        _make_completion_mock("not json"),
        _make_completion_mock(VALID_SCRIPT_JSON),
    ]
    from backend.services.llm_service import generate_script
    result = generate_script(vlm_output=[], language="en", llm_provider="gpt4o")
    assert mock_completion.call_count == 2
    assert "characters" in result

@patch("litellm.completion")
def test_generate_script_raises_after_two_bad_responses(mock_completion):
    """Both attempts return invalid JSON → raises ValueError."""
    mock_completion.return_value = _make_completion_mock("not json")
    from backend.services.llm_service import generate_script
    with pytest.raises(ValueError, match="LLM returned invalid JSON"):
        generate_script(vlm_output=[], language="en", llm_provider="gpt4o")
    assert mock_completion.call_count == 2

@patch("litellm.completion")
def test_generate_script_includes_language_in_prompt(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    generate_script(vlm_output=[], language="zh-TW", llm_provider="gpt4o")
    prompt_text = str(mock_completion.call_args)
    assert "zh-TW" in prompt_text
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
pytest tests/services/test_llm_service.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'backend.services.llm_service'`

- [ ] **Step 3: Implement `backend/services/llm_service.py`**

```python
import json
import litellm

_LLM_MODELS = {
    "gemini": "gemini/gemini-1.5-pro-latest",
    "gpt4o": "gpt-4o",
}

_SYSTEM_PROMPT = (
    "You are a children's audiobook script writer. Given the extracted story text from a "
    "picture book, output ONLY a JSON object (no markdown fences) with this exact structure:\n"
    '{"characters": [{"name": "...", "voice": "<alloy|echo|fable|onyx|nova|shimmer>", '
    '"traits": "..."}], "lines": [{"index": <0-based int>, "character": "...", '
    '"text": "...", "page": <1-based int>, "status": "pending"}]}\n'
    "Rules: Narrator is always present. Assign distinct voices to distinct characters. "
    "All dialogue text must be in the language specified by the user."
)

_STRICT_ADDENDUM = (
    "\n\nIMPORTANT: Your previous response was not valid JSON. "
    "Output ONLY the raw JSON object. No explanation, no markdown, no code fences."
)


def generate_script(vlm_output: list[dict], language: str, llm_provider: str) -> dict:
    """Call LLM to generate a structured script; retry once on malformed JSON."""
    model = _LLM_MODELS.get(llm_provider)
    if model is None:
        raise ValueError(f"Unknown llm_provider: {llm_provider!r}")

    user_content = (
        f"Language: {language}\n\n"
        f"Extracted story pages:\n{json.dumps(vlm_output, ensure_ascii=False)}"
    )

    for attempt in range(2):
        system = _SYSTEM_PROMPT + (_STRICT_ADDENDUM if attempt == 1 else "")
        response = litellm.completion(
            model=model,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user_content},
            ],
        )
        raw = response.choices[0].message.content
        try:
            data = json.loads(raw)
            # Ensure all lines start as pending
            for line in data.get("lines", []):
                line["status"] = "pending"
            return data
        except (json.JSONDecodeError, KeyError):
            if attempt == 1:
                raise ValueError(f"LLM returned invalid JSON: {raw!r}")

    raise ValueError("LLM returned invalid JSON after 2 attempts")  # unreachable
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
pytest tests/services/test_llm_service.py -v
```

Expected: 6 PASS

- [ ] **Step 5: Commit**

```bash
git add backend/services/llm_service.py tests/services/test_llm_service.py
git commit -m "feat: add LLM service with retry on malformed JSON"
```

---

### Task 4: TTS service unit

**Files:**
- Create: `backend/services/tts_service.py`
- Create: `tests/services/test_tts_service.py`

- [ ] **Step 1: Write the failing tests**

Create `tests/services/test_tts_service.py`:

```python
import asyncio
import base64
import pytest
from unittest.mock import patch, AsyncMock, MagicMock

FAKE_MP3 = b"\xff\xfb\x90\x00" * 100  # fake mp3 bytes

def _make_tts_response(content: bytes):
    mock = MagicMock()
    mock.content = content
    return mock

@pytest.mark.asyncio
async def test_generate_audio_returns_base64_for_all_lines():
    with patch("backend.services.tts_service._tts_client") as mock_client:
        mock_client.audio.speech.create = AsyncMock(return_value=_make_tts_response(FAKE_MP3))
        from backend.services.tts_service import generate_audio
        results = await generate_audio([
            {"index": 0, "text": "Hello", "voice": "alloy"},
            {"index": 1, "text": "World", "voice": "nova"},
        ])
    assert len(results) == 2
    assert results[0]["index"] == 0
    assert results[0]["status"] == "ready"
    assert results[0]["audio_b64"] == base64.b64encode(FAKE_MP3).decode()

@pytest.mark.asyncio
async def test_generate_audio_sets_error_on_tts_failure():
    with patch("backend.services.tts_service._tts_client") as mock_client:
        mock_client.audio.speech.create = AsyncMock(side_effect=Exception("API error"))
        from backend.services.tts_service import generate_audio
        results = await generate_audio([{"index": 0, "text": "Hello", "voice": "alloy"}])
    assert results[0]["status"] == "error"
    assert "audio_b64" not in results[0]

@pytest.mark.asyncio
async def test_generate_audio_preserves_order_under_concurrency():
    """Parallel calls must return results indexed correctly regardless of completion order."""
    call_count = 0
    async def slow_then_fast(*, model, input, voice, response_format):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            await asyncio.sleep(0.05)
        return _make_tts_response(FAKE_MP3)

    with patch("backend.services.tts_service._tts_client") as mock_client:
        mock_client.audio.speech.create = slow_then_fast
        from backend.services.tts_service import generate_audio
        results = await generate_audio([
            {"index": 0, "text": "First", "voice": "alloy"},
            {"index": 1, "text": "Second", "voice": "nova"},
        ])
    assert [r["index"] for r in results] == [0, 1]

@pytest.mark.asyncio
async def test_generate_audio_uses_mp3_format():
    with patch("backend.services.tts_service._tts_client") as mock_client:
        mock_client.audio.speech.create = AsyncMock(return_value=_make_tts_response(FAKE_MP3))
        from backend.services.tts_service import generate_audio
        await generate_audio([{"index": 0, "text": "Hi", "voice": "alloy"}])
    call_kwargs = mock_client.audio.speech.create.call_args.kwargs
    assert call_kwargs.get("response_format") == "mp3"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
pytest tests/services/test_tts_service.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'backend.services.tts_service'`

- [ ] **Step 3: Implement `backend/services/tts_service.py`**

```python
import asyncio
import base64
from openai import AsyncOpenAI
from backend.config import OPENAI_API_KEY

_tts_client = AsyncOpenAI(api_key=OPENAI_API_KEY or "dummy")


async def _generate_one(client, line: dict) -> dict:
    try:
        response = await client.audio.speech.create(
            model="tts-1",
            input=line["text"],
            voice=line["voice"],
            response_format="mp3",
        )
        audio_b64 = base64.b64encode(response.content).decode()
        return {"index": line["index"], "status": "ready", "audio_b64": audio_b64}
    except Exception:
        return {"index": line["index"], "status": "error"}


async def generate_audio(lines: list[dict]) -> list[dict]:
    """Generate TTS audio in parallel for all lines; returns results in original index order."""
    tasks = [_generate_one(_tts_client, line) for line in lines]
    results = await asyncio.gather(*tasks)
    return sorted(results, key=lambda r: r["index"])
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
pytest tests/services/test_tts_service.py -v
```

Expected: 4 PASS

- [ ] **Step 5: Commit**

```bash
git add backend/services/tts_service.py tests/services/test_tts_service.py
git commit -m "feat: add TTS service with parallel asyncio.gather"
```

---

### Task 5: `/analyze` endpoint

**Files:**
- Create: `backend/routers/__init__.py`
- Create: `backend/routers/analyze.py`
- Create: `tests/test_analyze.py`
- Modify: `backend/main.py`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_analyze.py`:

```python
import pytest
from unittest.mock import patch

FAKE_PAGES = [{"page": 1, "text": "Once upon a time"}, {"page": 2, "text": "The end"}]

def _fake_image():
    """Minimal valid JPEG bytes."""
    return b"\xff\xd8\xff\xe0" + b"\x00" * 100

@patch("backend.routers.analyze.analyze_pages", return_value=FAKE_PAGES)
def test_analyze_returns_pages(mock_svc, client):
    response = client.post(
        "/analyze",
        data={"vlm_provider": "gemini"},
        files=[("images", ("page1.jpg", _fake_image(), "image/jpeg"))],
    )
    assert response.status_code == 200
    assert response.json() == {"pages": FAKE_PAGES}

@patch("backend.routers.analyze.analyze_pages", return_value=FAKE_PAGES)
def test_analyze_passes_bytes_to_service(mock_svc, client):
    img = _fake_image()
    client.post(
        "/analyze",
        data={"vlm_provider": "gpt4o"},
        files=[("images", ("p1.jpg", img, "image/jpeg"))],
    )
    mock_svc.assert_called_once_with(
        image_bytes_list=[img],
        vlm_provider="gpt4o",
    )

@patch("backend.routers.analyze.analyze_pages", side_effect=ValueError("VLM returned invalid JSON"))
def test_analyze_returns_422_on_vlm_error(mock_svc, client):
    response = client.post(
        "/analyze",
        data={"vlm_provider": "gemini"},
        files=[("images", ("p1.jpg", _fake_image(), "image/jpeg"))],
    )
    assert response.status_code == 422

def test_analyze_requires_images(client):
    response = client.post("/analyze", data={"vlm_provider": "gemini"})
    assert response.status_code == 422

def test_analyze_requires_vlm_provider(client):
    response = client.post(
        "/analyze",
        files=[("images", ("p1.jpg", b"\xff\xd8", "image/jpeg"))],
    )
    assert response.status_code == 422
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
pytest tests/test_analyze.py -v
```

Expected: FAIL — routes not yet registered

- [ ] **Step 3: Create `backend/routers/__init__.py`** (empty — must exist before the router module)

```bash
mkdir -p backend/routers && touch backend/routers/__init__.py
```

- [ ] **Step 4: Create `backend/routers/analyze.py`**

```python
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from typing import Annotated
from backend.services.vlm_service import analyze_pages

router = APIRouter()


@router.post("/analyze")
async def analyze(
    images: Annotated[list[UploadFile], File()],
    vlm_provider: Annotated[str, Form()],
):
    image_bytes_list = [await img.read() for img in images]
    try:
        pages = analyze_pages(
            image_bytes_list=image_bytes_list,
            vlm_provider=vlm_provider,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"pages": pages}
```

- [ ] **Step 5: Register router in `backend/main.py`**

```python
from fastapi import FastAPI
from backend.routers.analyze import router as analyze_router

app = FastAPI(title="BookActor Backend")
app.include_router(analyze_router)

@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
pytest tests/test_analyze.py tests/test_health.py -v
```

Expected: 6 PASS

- [ ] **Step 7: Commit**

```bash
git add backend/routers/ backend/main.py tests/test_analyze.py
git commit -m "feat: add /analyze endpoint"
```

---

### Task 6: `/script` endpoint

**Files:**
- Create: `backend/routers/script.py`
- Create: `tests/test_script.py`
- Modify: `backend/main.py`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_script.py`:

```python
import pytest
from unittest.mock import patch

FAKE_SCRIPT = {
    "characters": [{"name": "Narrator", "voice": "alloy"}],
    "lines": [{"index": 0, "character": "Narrator", "text": "Once.", "page": 1, "status": "pending"}],
}

@patch("backend.routers.script.generate_script", return_value=FAKE_SCRIPT)
def test_script_returns_script(mock_svc, client):
    payload = {
        "vlm_output": [{"page": 1, "text": "Once upon a time"}],
        "language": "en",
        "llm_provider": "gpt4o",
    }
    response = client.post("/script", json=payload)
    assert response.status_code == 200
    assert response.json() == {"script": FAKE_SCRIPT}

@patch("backend.routers.script.generate_script", return_value=FAKE_SCRIPT)
def test_script_passes_params_to_service(mock_svc, client):
    vlm_output = [{"page": 1, "text": "Hello"}]
    client.post("/script", json={"vlm_output": vlm_output, "language": "zh", "llm_provider": "gemini"})
    mock_svc.assert_called_once_with(
        vlm_output=vlm_output,
        language="zh",
        llm_provider="gemini",
    )

@patch("backend.routers.script.generate_script", side_effect=ValueError("LLM returned invalid JSON"))
def test_script_returns_422_on_llm_error(mock_svc, client):
    response = client.post(
        "/script",
        json={"vlm_output": [], "language": "en", "llm_provider": "gpt4o"},
    )
    assert response.status_code == 422

def test_script_requires_all_fields(client):
    response = client.post("/script", json={"language": "en"})
    assert response.status_code == 422
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
pytest tests/test_script.py -v
```

Expected: FAIL — route not registered

- [ ] **Step 3: Create `backend/routers/script.py`**

```python
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
    try:
        result = generate_script(
            vlm_output=req.vlm_output,
            language=req.language,
            llm_provider=req.llm_provider,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"script": result}
```

- [ ] **Step 4: Register router in `backend/main.py`**

```python
from fastapi import FastAPI
from backend.routers.analyze import router as analyze_router
from backend.routers.script import router as script_router

app = FastAPI(title="BookActor Backend")
app.include_router(analyze_router)
app.include_router(script_router)

@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
pytest tests/test_analyze.py tests/test_script.py tests/test_health.py -v
```

Expected: 10 PASS

- [ ] **Step 6: Commit**

```bash
git add backend/routers/script.py backend/main.py tests/test_script.py
git commit -m "feat: add /script endpoint"
```

---

### Task 7: `/tts` endpoint

**Files:**
- Create: `backend/routers/tts.py`
- Create: `tests/test_tts.py`
- Modify: `backend/main.py`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_tts.py`:

```python
import pytest
from unittest.mock import patch, AsyncMock

FAKE_AUDIO_RESULTS = [
    {"index": 0, "status": "ready", "audio_b64": "AAAA"},
    {"index": 1, "status": "error"},
]

@patch("backend.routers.tts.generate_audio", new_callable=AsyncMock, return_value=FAKE_AUDIO_RESULTS)
def test_tts_returns_audio_list(mock_svc, client):
    payload = {
        "lines": [
            {"index": 0, "text": "Hello", "voice": "alloy"},
            {"index": 1, "text": "World", "voice": "nova"},
        ]
    }
    response = client.post("/tts", json=payload)
    assert response.status_code == 200
    assert response.json() == FAKE_AUDIO_RESULTS

@patch("backend.routers.tts.generate_audio", new_callable=AsyncMock, return_value=FAKE_AUDIO_RESULTS)
def test_tts_passes_lines_to_service(mock_svc, client):
    lines = [{"index": 0, "text": "Hi", "voice": "alloy"}]
    client.post("/tts", json={"lines": lines})
    mock_svc.assert_called_once_with(lines)

def test_tts_requires_lines_field(client):
    response = client.post("/tts", json={})
    assert response.status_code == 422

def test_tts_requires_index_text_voice(client):
    response = client.post("/tts", json={"lines": [{"index": 0}]})
    assert response.status_code == 422
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
pytest tests/test_tts.py -v
```

Expected: FAIL — route not registered

- [ ] **Step 3: Create `backend/routers/tts.py`**

```python
from fastapi import APIRouter
from pydantic import BaseModel
from backend.services.tts_service import generate_audio

router = APIRouter()


class TtsLine(BaseModel):
    index: int
    text: str
    voice: str


class TtsRequest(BaseModel):
    lines: list[TtsLine]


@router.post("/tts")
async def tts(req: TtsRequest):
    lines = [line.model_dump() for line in req.lines]
    return await generate_audio(lines)
```

- [ ] **Step 4: Register router in `backend/main.py`**

```python
from fastapi import FastAPI
from backend.routers.analyze import router as analyze_router
from backend.routers.script import router as script_router
from backend.routers.tts import router as tts_router

app = FastAPI(title="BookActor Backend")
app.include_router(analyze_router)
app.include_router(script_router)
app.include_router(tts_router)

@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
pytest tests/ -v
```

Expected: all PASS

- [ ] **Step 6: Commit**

```bash
git add backend/routers/tts.py backend/main.py tests/test_tts.py
git commit -m "feat: add /tts endpoint"
```

---

### Task 8: Full test run and verification

**Files:**
- No new files — verification only

- [ ] **Step 1: Run the full test suite**

```bash
cd D:/developer_tools/bookactor/.worktrees/phase3-fastapi-backend
pytest tests/ -v --tb=short
```

Expected: all tests PASS, zero failures

- [ ] **Step 2: Verify app starts (run from repo root, not from inside backend/)**

```bash
# Run from the worktree root so that absolute imports (e.g. `from backend.config import ...`) resolve correctly
uvicorn backend.main:app --reload --port 8000 &
sleep 2
curl http://localhost:8000/health
```

Expected: `{"status":"ok"}`

Kill the server after verification:
```bash
pkill -f "uvicorn backend.main:app"
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: all backend tests passing, ready for Phase 3b integration"
```
