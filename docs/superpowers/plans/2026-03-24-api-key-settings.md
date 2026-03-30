# API Key Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users enter OpenAI and Google API keys once via a Settings screen; store them in the OS credential store; send them in every backend request body instead of relying on `.env`.

**Architecture:** `flutter_secure_storage` holds keys on the client. A `SettingsService` wraps the storage. Riverpod providers expose an `ApiService` pre-loaded with the keys. Each backend endpoint accepts keys as request fields and passes them directly to `litellm` / `AsyncOpenAI`. The backend VLM service also gains `processing_mode` support, closing a pre-existing gap.

**Tech Stack:** Flutter, `flutter_secure_storage ^9.0.0`, Riverpod (`FutureProvider`), GoRouter, Python FastAPI, `litellm`, `openai` SDK.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `backend/services/vlm_service.py` | Modify | Accept `processing_mode`, `openai_api_key`, `google_api_key`; route key + prompt |
| `backend/routers/analyze.py` | Modify | Accept all three new form fields |
| `backend/services/llm_service.py` | Modify | Accept `openai_api_key`, `google_api_key`; route key to litellm |
| `backend/routers/script.py` | Modify | Add key fields to `ScriptRequest` |
| `backend/services/tts_service.py` | Modify | Remove module-level client; accept `openai_api_key` |
| `backend/routers/tts.py` | Modify | Add `openai_api_key` to `TtsRequest` |
| `pubspec.yaml` | Modify | Add `flutter_secure_storage` |
| `lib/services/settings_service.dart` | **Create** | `SettingsService` wrapping `flutter_secure_storage` |
| `lib/providers/settings_provider.dart` | **Create** | Four Riverpod providers |
| `lib/screens/settings_screen.dart` | **Create** | Settings UI |
| `lib/services/api_service.dart` | Modify | Add `openAiKey`, `googleKey` constructor fields; include in request bodies |
| `lib/main.dart` | Modify | Await `hasKeys()`, override `initialLocationProvider` |
| `lib/app.dart` | Modify | Add `/settings` route; read `initialLocationProvider` |
| `lib/screens/library_screen.dart` | Modify | Gear icon in AppBar |
| `lib/screens/loading_screen.dart` | Modify | `ConsumerStatefulWidget`; resolve `ApiService` via provider |
| `lib/screens/upload_screen.dart` | Modify | Add keys guard + hint text to Generate button |
| `tests/test_analyze.py` | Modify | Add new fields to requests; update assertions |
| `tests/test_script.py` | Modify | Add keys to requests; update assertions |
| `tests/test_tts.py` | Modify | Add `openai_api_key`; update assertions |
| `tests/services/test_vlm_service.py` | Modify | Add params; add `api_key`/`processing_mode` assertions |
| `tests/services/test_llm_service.py` | Modify | Add params; add `api_key` assertion |
| `tests/services/test_tts_service.py` | Modify | Replace `_tts_client` patch with `AsyncOpenAI` class patch |
| `test/services/api_service_test.dart` | Modify | Add `openAiKey`/`googleKey` to all `ApiService(...)` calls; assert keys in body |
| `test/screens/loading_screen_live_test.dart` | Modify | Update `_RecordingApiService` super constructor |

---

## Task 1: Backend VLM — processing_mode + API key routing

**Files:**
- Modify: `backend/services/vlm_service.py`
- Modify: `backend/routers/analyze.py`
- Modify: `tests/services/test_vlm_service.py`
- Modify: `tests/test_analyze.py`

### Background

`vlm_service.analyze_pages()` currently ignores `processing_mode` (it was never wired on the backend). The `/analyze` router currently accepts only `vlm_provider`. Both gaps are fixed here.

Two system prompts are needed:
- `text_heavy` → OCR-focused, ignore illustrations
- `picture_book` → visual narrative: analyze illustrations, character emotions, and any visible text

---

- [ ] **Step 1: Update `test_vlm_service.py` — add new params and assertions**

Replace the entire contents of `tests/services/test_vlm_service.py`:

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
        processing_mode="text_heavy",
        openai_api_key="sk-test",
        google_api_key="goog-test",
    )
    assert result == [{"page": 1, "text": "Once upon a time"}, {"page": 2, "text": "The end"}]
    mock_completion.assert_called_once()
    call_kwargs = mock_completion.call_args.kwargs
    assert call_kwargs["model"].startswith("gemini")
    assert call_kwargs["api_key"] == "goog-test"

@patch("litellm.completion")
def test_analyze_gpt4o_uses_openai_key(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(
        image_bytes_list=[b"fakejpeg"],
        vlm_provider="gpt4o",
        processing_mode="text_heavy",
        openai_api_key="sk-openai",
        google_api_key="goog-test",
    )
    call_kwargs = mock_completion.call_args.kwargs
    assert "gpt-4o" in call_kwargs["model"]
    assert call_kwargs["api_key"] == "sk-openai"

@patch("litellm.completion")
def test_analyze_picture_book_mode_uses_different_prompt(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(
        image_bytes_list=[b"fakejpeg"],
        vlm_provider="gemini",
        processing_mode="picture_book",
        openai_api_key="sk-test",
        google_api_key="goog-test",
    )
    call_kwargs = mock_completion.call_args.kwargs
    system_content = call_kwargs["messages"][0]["content"]
    # picture_book prompt should mention illustrations/narrative, not pure OCR
    assert "illustration" in system_content.lower() or "narrative" in system_content.lower()

@patch("litellm.completion")
def test_analyze_text_heavy_mode_uses_ocr_prompt(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(
        image_bytes_list=[b"fakejpeg"],
        vlm_provider="gemini",
        processing_mode="text_heavy",
        openai_api_key="sk-test",
        google_api_key="goog-test",
    )
    call_kwargs = mock_completion.call_args.kwargs
    system_content = call_kwargs["messages"][0]["content"]
    assert "text" in system_content.lower()

@patch("litellm.completion")
def test_analyze_encodes_images_as_base64(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(
        image_bytes_list=[b"fakejpeg", b"fakejpeg2"],
        vlm_provider="gemini",
        processing_mode="text_heavy",
        openai_api_key="",
        google_api_key="goog-test",
    )
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
        analyze_pages(
            image_bytes_list=[b"fakejpeg"],
            vlm_provider="gemini",
            processing_mode="text_heavy",
            openai_api_key="",
            google_api_key="goog-test",
        )

@patch("litellm.completion")
def test_analyze_raises_on_unknown_provider(mock_completion):
    from backend.services.vlm_service import analyze_pages
    with pytest.raises(ValueError, match="Unknown vlm_provider"):
        analyze_pages(
            image_bytes_list=[b"fakejpeg"],
            vlm_provider="unknown_provider",
            processing_mode="text_heavy",
            openai_api_key="",
            google_api_key="",
        )
    mock_completion.assert_not_called()
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd D:/developer_tools/bookactor
python -m pytest tests/services/test_vlm_service.py -v
```
Expected: failures — `analyze_pages()` does not yet accept new params.

- [ ] **Step 3: Update `vlm_service.py`**

Replace the entire file `backend/services/vlm_service.py`:

```python
import base64
import json
import litellm

_VLM_MODELS = {
    "gemini": "gemini/gemini-1.5-pro-latest",
    "gpt4o": "gpt-4o",
}

_SYSTEM_PROMPT_TEXT_HEAVY = (
    "You are a children's book reader. Analyse every page image provided and "
    "extract ONLY the text visible on each page, ignoring background illustrations. "
    "Return ONLY a JSON object with this exact structure, no markdown fences:\n"
    '{"pages": [{"page": <1-based int>, "text": "<all visible text from that page>"}]}'
)

_SYSTEM_PROMPT_PICTURE_BOOK = (
    "You are a children's picture book narrator. For each page image provided, "
    "analyse the illustrations, character emotions, and scene composition. "
    "Also extract any visible text on the page as a supporting detail. "
    "Combine both to generate a cohesive, imaginative narrative for that page. "
    "Return ONLY a JSON object with this exact structure, no markdown fences:\n"
    '{"pages": [{"page": <1-based int>, "text": "<generated narrative for that page>"}]}'
)

_SYSTEM_PROMPTS = {
    "text_heavy": _SYSTEM_PROMPT_TEXT_HEAVY,
    "picture_book": _SYSTEM_PROMPT_PICTURE_BOOK,
}


def analyze_pages(
    image_bytes_list: list[bytes],
    vlm_provider: str,
    processing_mode: str,
    openai_api_key: str,
    google_api_key: str,
) -> list[dict]:
    """Call VLM with page images; return list of {page, text} dicts."""
    model = _VLM_MODELS.get(vlm_provider)
    if model is None:
        raise ValueError(f"Unknown vlm_provider: {vlm_provider!r}")

    system_prompt = _SYSTEM_PROMPTS.get(processing_mode, _SYSTEM_PROMPT_TEXT_HEAVY)
    api_key = openai_api_key if vlm_provider == "gpt4o" else google_api_key

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
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": image_content},
        ],
        api_key=api_key,
    )
    raw = response.choices[0].message.content
    try:
        data = json.loads(raw)
        return data["pages"]
    except (json.JSONDecodeError, KeyError) as exc:
        raise ValueError(f"VLM returned invalid JSON: {raw!r}") from exc
```

- [ ] **Step 4: Run VLM service tests — expect pass**

```bash
python -m pytest tests/services/test_vlm_service.py -v
```
Expected: all 6 tests pass.

- [ ] **Step 5: Update `test_analyze.py`**

Replace the entire file `tests/test_analyze.py`:

```python
import pytest
from unittest.mock import patch

FAKE_PAGES = [{"page": 1, "text": "Once upon a time"}, {"page": 2, "text": "The end"}]

def _fake_image():
    return b"\xff\xd8\xff\xe0" + b"\x00" * 100

@patch("backend.routers.analyze.analyze_pages", return_value=FAKE_PAGES)
def test_analyze_returns_pages(mock_svc, client):
    response = client.post(
        "/analyze",
        data={"vlm_provider": "gemini", "processing_mode": "text_heavy",
              "openai_api_key": "sk-test", "google_api_key": "goog-test"},
        files=[("images", ("page1.jpg", _fake_image(), "image/jpeg"))],
    )
    assert response.status_code == 200
    assert response.json() == {"pages": FAKE_PAGES}

@patch("backend.routers.analyze.analyze_pages", return_value=FAKE_PAGES)
def test_analyze_passes_all_params_to_service(mock_svc, client):
    img = _fake_image()
    client.post(
        "/analyze",
        data={"vlm_provider": "gpt4o", "processing_mode": "picture_book",
              "openai_api_key": "sk-openai", "google_api_key": "goog-test"},
        files=[("images", ("p1.jpg", img, "image/jpeg"))],
    )
    mock_svc.assert_called_once_with(
        image_bytes_list=[img],
        vlm_provider="gpt4o",
        processing_mode="picture_book",
        openai_api_key="sk-openai",
        google_api_key="goog-test",
    )

@patch("backend.routers.analyze.analyze_pages", side_effect=ValueError("VLM returned invalid JSON"))
def test_analyze_returns_422_on_vlm_error(mock_svc, client):
    response = client.post(
        "/analyze",
        data={"vlm_provider": "gemini", "processing_mode": "text_heavy",
              "openai_api_key": "", "google_api_key": "goog-test"},
        files=[("images", ("p1.jpg", _fake_image(), "image/jpeg"))],
    )
    assert response.status_code == 422

def test_analyze_requires_images(client):
    response = client.post("/analyze", data={"vlm_provider": "gemini",
        "processing_mode": "text_heavy", "openai_api_key": "", "google_api_key": ""})
    assert response.status_code == 422

def test_analyze_requires_vlm_provider(client):
    response = client.post(
        "/analyze",
        data={"processing_mode": "text_heavy", "openai_api_key": "", "google_api_key": ""},
        files=[("images", ("p1.jpg", b"\xff\xd8", "image/jpeg"))],
    )
    assert response.status_code == 422
```

- [ ] **Step 6: Run router tests — expect failures**

```bash
python -m pytest tests/test_analyze.py -v
```
Expected: failures — router doesn't accept new fields yet.

- [ ] **Step 7: Update `analyze.py` router**

Replace `backend/routers/analyze.py`:

```python
import asyncio
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from typing import Annotated
from backend.services.vlm_service import analyze_pages

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
    return {"pages": pages}
```

- [ ] **Step 8: Run all backend analyze tests — expect pass**

```bash
python -m pytest tests/test_analyze.py tests/services/test_vlm_service.py -v
```
Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add backend/services/vlm_service.py backend/routers/analyze.py tests/services/test_vlm_service.py tests/test_analyze.py
git commit -m "feat: wire processing_mode and API keys through VLM service and analyze router"
```

---

## Task 2: Backend LLM — API key routing

**Files:**
- Modify: `backend/services/llm_service.py`
- Modify: `backend/routers/script.py`
- Modify: `tests/services/test_llm_service.py`
- Modify: `tests/test_script.py`

- [ ] **Step 1: Update `test_llm_service.py` — add key params and api_key assertion**

Replace the entire file `tests/services/test_llm_service.py`:

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
        openai_api_key="sk-test",
        google_api_key="goog-test",
    )
    assert "characters" in result
    assert "lines" in result
    assert result["lines"][0]["status"] == "pending"

@patch("litellm.completion")
def test_generate_script_uses_gpt4o_model_and_openai_key(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    generate_script(vlm_output=[], language="en", llm_provider="gpt4o",
                    openai_api_key="sk-openai", google_api_key="goog-test")
    call_kwargs = mock_completion.call_args.kwargs
    assert "gpt-4o" in call_kwargs["model"]
    assert call_kwargs["api_key"] == "sk-openai"

@patch("litellm.completion")
def test_generate_script_uses_gemini_model_and_google_key(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    generate_script(vlm_output=[], language="zh", llm_provider="gemini",
                    openai_api_key="sk-test", google_api_key="goog-key")
    call_kwargs = mock_completion.call_args.kwargs
    assert "gemini" in call_kwargs["model"]
    assert call_kwargs["api_key"] == "goog-key"

@patch("litellm.completion")
def test_generate_script_retries_once_on_bad_json(mock_completion):
    mock_completion.side_effect = [
        _make_completion_mock("not json"),
        _make_completion_mock(VALID_SCRIPT_JSON),
    ]
    from backend.services.llm_service import generate_script
    result = generate_script(vlm_output=[], language="en", llm_provider="gpt4o",
                             openai_api_key="sk-test", google_api_key="")
    assert mock_completion.call_count == 2
    assert "characters" in result

@patch("litellm.completion")
def test_generate_script_raises_after_two_bad_responses(mock_completion):
    mock_completion.return_value = _make_completion_mock("not json")
    from backend.services.llm_service import generate_script
    with pytest.raises(ValueError, match="LLM returned invalid JSON"):
        generate_script(vlm_output=[], language="en", llm_provider="gpt4o",
                        openai_api_key="sk-test", google_api_key="")
    assert mock_completion.call_count == 2

@patch("litellm.completion")
def test_generate_script_includes_language_in_prompt(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    generate_script(vlm_output=[], language="zh-TW", llm_provider="gpt4o",
                    openai_api_key="sk-test", google_api_key="")
    prompt_text = str(mock_completion.call_args)
    assert "zh-TW" in prompt_text
```

- [ ] **Step 2: Run tests — expect failures**

```bash
python -m pytest tests/services/test_llm_service.py -v
```
Expected: failures — `generate_script()` doesn't accept key params yet.

- [ ] **Step 3: Update `llm_service.py`**

Replace `backend/services/llm_service.py`:

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


def generate_script(
    vlm_output: list[dict],
    language: str,
    llm_provider: str,
    openai_api_key: str,
    google_api_key: str,
) -> dict:
    """Call LLM to generate a structured script; retry once on malformed JSON."""
    model = _LLM_MODELS.get(llm_provider)
    if model is None:
        raise ValueError(f"Unknown llm_provider: {llm_provider!r}")

    api_key = openai_api_key if llm_provider == "gpt4o" else google_api_key

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
            api_key=api_key,
        )
        raw = response.choices[0].message.content
        try:
            data = json.loads(raw)
            for line in data.get("lines", []):
                line["status"] = "pending"
            return data
        except (json.JSONDecodeError, KeyError) as exc:
            if attempt == 1:
                raise ValueError(f"LLM returned invalid JSON: {raw!r}") from exc

    raise ValueError("LLM returned invalid JSON after 2 attempts")
```

- [ ] **Step 4: Update `test_script.py`**

Replace `tests/test_script.py`:

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
        "openai_api_key": "sk-test",
        "google_api_key": "goog-test",
    }
    response = client.post("/script", json=payload)
    assert response.status_code == 200
    assert response.json() == {"script": FAKE_SCRIPT}

@patch("backend.routers.script.generate_script", return_value=FAKE_SCRIPT)
def test_script_passes_all_params_to_service(mock_svc, client):
    vlm_output = [{"page": 1, "text": "Hello"}]
    client.post("/script", json={
        "vlm_output": vlm_output, "language": "zh", "llm_provider": "gemini",
        "openai_api_key": "sk-test", "google_api_key": "goog-key",
    })
    mock_svc.assert_called_once_with(
        vlm_output=vlm_output,
        language="zh",
        llm_provider="gemini",
        openai_api_key="sk-test",
        google_api_key="goog-key",
    )

@patch("backend.routers.script.generate_script", side_effect=ValueError("LLM returned invalid JSON"))
def test_script_returns_422_on_llm_error(mock_svc, client):
    response = client.post("/script", json={
        "vlm_output": [], "language": "en", "llm_provider": "gpt4o",
        "openai_api_key": "", "google_api_key": "",
    })
    assert response.status_code == 422

def test_script_requires_all_fields(client):
    response = client.post("/script", json={"language": "en"})
    assert response.status_code == 422
```

- [ ] **Step 5: Update `script.py` router**

Replace `backend/routers/script.py`:

```python
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from backend.services.llm_service import generate_script

router = APIRouter()


class ScriptRequest(BaseModel):
    vlm_output: list[dict]
    language: str
    llm_provider: str
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
            openai_api_key=req.openai_api_key,
            google_api_key=req.google_api_key,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"script": result}
```

- [ ] **Step 6: Run all LLM tests — expect pass**

```bash
python -m pytest tests/test_script.py tests/services/test_llm_service.py -v
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add backend/services/llm_service.py backend/routers/script.py tests/services/test_llm_service.py tests/test_script.py
git commit -m "feat: wire API keys through LLM service and script router"
```

---

## Task 3: Backend TTS — remove singleton, accept API key

**Files:**
- Modify: `backend/services/tts_service.py`
- Modify: `backend/routers/tts.py`
- Modify: `tests/services/test_tts_service.py`
- Modify: `tests/test_tts.py`

### Background

`tts_service.py` currently creates a module-level `_tts_client = AsyncOpenAI(api_key=OPENAI_API_KEY)` at import time. This is replaced with a per-request client created inside `generate_audio()`. The `_generate_one` helper already accepts `client` as its first arg — that doesn't change.

The tests currently patch `backend.services.tts_service._tts_client`. After removal, they patch `backend.services.tts_service.AsyncOpenAI` instead.

- [ ] **Step 1: Update `test_tts_service.py`**

Replace the entire file `tests/services/test_tts_service.py`:

```python
import asyncio
import base64
import pytest
from unittest.mock import patch, AsyncMock, MagicMock

FAKE_MP3 = b"\xff\xfb\x90\x00" * 100

def _make_tts_response(content: bytes):
    mock = MagicMock()
    mock.content = content
    return mock

def _make_openai_client_mock(speech_side_effect=None, speech_return=None):
    """Create a mock AsyncOpenAI client with audio.speech.create configured."""
    mock_client = MagicMock()
    if speech_side_effect is not None:
        mock_client.audio.speech.create = AsyncMock(side_effect=speech_side_effect)
    else:
        mock_client.audio.speech.create = AsyncMock(return_value=speech_return or _make_tts_response(FAKE_MP3))
    return mock_client

@pytest.mark.asyncio
async def test_generate_audio_returns_base64_for_all_lines():
    mock_client = _make_openai_client_mock()
    with patch("backend.services.tts_service.AsyncOpenAI", return_value=mock_client):
        from backend.services.tts_service import generate_audio
        results = await generate_audio(
            lines=[
                {"index": 0, "text": "Hello", "voice": "alloy"},
                {"index": 1, "text": "World", "voice": "nova"},
            ],
            openai_api_key="sk-test",
        )
    assert len(results) == 2
    assert results[0]["index"] == 0
    assert results[0]["status"] == "ready"
    assert results[0]["audio_b64"] == base64.b64encode(FAKE_MP3).decode()

@pytest.mark.asyncio
async def test_generate_audio_creates_client_with_provided_key():
    mock_client = _make_openai_client_mock()
    with patch("backend.services.tts_service.AsyncOpenAI", return_value=mock_client) as mock_cls:
        from backend.services.tts_service import generate_audio
        await generate_audio(lines=[], openai_api_key="sk-my-key")
    mock_cls.assert_called_once_with(api_key="sk-my-key")

@pytest.mark.asyncio
async def test_generate_audio_sets_error_on_tts_failure():
    mock_client = _make_openai_client_mock(speech_side_effect=Exception("API error"))
    with patch("backend.services.tts_service.AsyncOpenAI", return_value=mock_client):
        from backend.services.tts_service import generate_audio
        results = await generate_audio(
            lines=[{"index": 0, "text": "Hello", "voice": "alloy"}],
            openai_api_key="sk-test",
        )
    assert results[0]["status"] == "error"
    assert "audio_b64" not in results[0]

@pytest.mark.asyncio
async def test_generate_audio_preserves_order_under_concurrency():
    call_count = 0
    async def slow_then_fast(*, model, input, voice, response_format):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            await asyncio.sleep(0.05)
        return _make_tts_response(FAKE_MP3)

    mock_client = MagicMock()
    mock_client.audio.speech.create = slow_then_fast
    with patch("backend.services.tts_service.AsyncOpenAI", return_value=mock_client):
        from backend.services.tts_service import generate_audio
        results = await generate_audio(
            lines=[
                {"index": 0, "text": "First", "voice": "alloy"},
                {"index": 1, "text": "Second", "voice": "nova"},
            ],
            openai_api_key="sk-test",
        )
    assert [r["index"] for r in results] == [0, 1]

@pytest.mark.asyncio
async def test_generate_audio_uses_mp3_format():
    mock_client = _make_openai_client_mock()
    with patch("backend.services.tts_service.AsyncOpenAI", return_value=mock_client):
        from backend.services.tts_service import generate_audio
        await generate_audio(
            lines=[{"index": 0, "text": "Hi", "voice": "alloy"}],
            openai_api_key="sk-test",
        )
    call_kwargs = mock_client.audio.speech.create.call_args.kwargs
    assert call_kwargs.get("response_format") == "mp3"
```

- [ ] **Step 2: Run tests — expect failures**

```bash
python -m pytest tests/services/test_tts_service.py -v
```
Expected: failures — `_tts_client` still exists; `generate_audio` doesn't accept `openai_api_key`.

- [ ] **Step 3: Update `tts_service.py`**

Replace `backend/services/tts_service.py`:

```python
import asyncio
import base64
from openai import AsyncOpenAI


async def _generate_one(client: AsyncOpenAI, line: dict) -> dict:
    """Generate TTS audio for one line; returns status dict with optional audio_b64."""
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


async def generate_audio(lines: list[dict], openai_api_key: str) -> list[dict]:
    """Generate TTS audio in parallel for all lines; returns results in original index order."""
    client = AsyncOpenAI(api_key=openai_api_key)
    tasks = [_generate_one(client, line) for line in lines]
    results = await asyncio.gather(*tasks)
    return sorted(results, key=lambda r: r["index"])
```

- [ ] **Step 4: Update `test_tts.py`**

Replace `tests/test_tts.py`:

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
        ],
        "openai_api_key": "sk-test",
    }
    response = client.post("/tts", json=payload)
    assert response.status_code == 200
    assert response.json() == FAKE_AUDIO_RESULTS

@patch("backend.routers.tts.generate_audio", new_callable=AsyncMock, return_value=FAKE_AUDIO_RESULTS)
def test_tts_passes_lines_and_key_to_service(mock_svc, client):
    lines = [{"index": 0, "text": "Hi", "voice": "alloy"}]
    client.post("/tts", json={"lines": lines, "openai_api_key": "sk-my-key"})
    mock_svc.assert_called_once_with(lines=lines, openai_api_key="sk-my-key")

def test_tts_requires_lines_field(client):
    response = client.post("/tts", json={"openai_api_key": "sk-test"})
    assert response.status_code == 422

def test_tts_requires_index_text_voice(client):
    response = client.post("/tts", json={"lines": [{"index": 0}], "openai_api_key": ""})
    assert response.status_code == 422
```

- [ ] **Step 5: Update `tts.py` router**

Replace `backend/routers/tts.py`:

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
    openai_api_key: str


@router.post("/tts")
async def tts(req: TtsRequest):
    """Generate TTS audio for all lines in parallel."""
    lines = [line.model_dump() for line in req.lines]
    return await generate_audio(lines=lines, openai_api_key=req.openai_api_key)
```

- [ ] **Step 6: Run all TTS tests — expect pass**

```bash
python -m pytest tests/test_tts.py tests/services/test_tts_service.py -v
```
Expected: all tests pass.

- [ ] **Step 7: Run full backend test suite**

```bash
python -m pytest -v
```
Expected: all backend tests pass.

- [ ] **Step 8: Commit**

```bash
git add backend/services/tts_service.py backend/routers/tts.py tests/services/test_tts_service.py tests/test_tts.py
git commit -m "feat: remove TTS singleton, accept openai_api_key per request"
```

---

## Task 4: Flutter — ApiService constructor fields + tests

**Files:**
- Modify: `lib/services/api_service.dart`
- Modify: `test/services/api_service_test.dart`
- Modify: `test/screens/loading_screen_live_test.dart`

### Background

`ApiService` gains two required constructor fields. Each method reads keys from `this.openAiKey` / `this.googleKey` and includes them in the request body. No method-level parameters are added.

`api_service_test.dart` constructs `ApiService` in 5 places — all need the new fields. `loading_screen_live_test.dart`'s `_RecordingApiService` subclass has a `super(baseUrl: 'http://fake')` call that will fail to compile.

- [ ] **Step 1: Update `api_service_test.dart`**

Open `test/services/api_service_test.dart`. Make the following changes:

1. Update the `analyzePages - sends images` test: add `openAiKey` / `googleKey` to the `ApiService` constructor, assert keys appear in body, add `processingMode` param:

Replace the entire file with:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookactor/services/api_service.dart';
import 'package:bookactor/models/processing_mode.dart';

void main() {
  const baseUrl = 'http://localhost:8000';

  ApiService makeService(MockClient client) => ApiService(
        baseUrl: baseUrl,
        openAiKey: 'test-openai-key',
        googleKey: 'test-google-key',
        client: client,
      );

  group('analyzePages', () {
    test('sends images as multipart and returns pages list', () async {
      final fakePages = [
        {'page': 1, 'text': 'Once upon a time'}
      ];
      final client = MockClient((request) async {
        expect(request.url.path, '/analyze');
        expect(request.method, 'POST');
        final bodyStr = String.fromCharCodes(request.bodyBytes);
        expect(bodyStr, contains('processing_mode'));
        expect(bodyStr, contains('text_heavy'));
        expect(bodyStr, contains('openai_api_key'));
        expect(bodyStr, contains('test-openai-key'));
        expect(bodyStr, contains('google_api_key'));
        expect(bodyStr, contains('test-google-key'));
        return http.Response(
          jsonEncode({'pages': fakePages}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = makeService(client);
      final result = await service.analyzePages(
        imageBytesList: [Uint8List.fromList([0, 1, 2])],
        vlmProvider: 'gemini',
        processingMode: ProcessingMode.textHeavy,
      );
      expect(result, fakePages);
    });

    test('throws ApiException on non-200 response', () async {
      final client = MockClient((_) async => http.Response('error', 422));
      final service = makeService(client);
      await expectLater(
        () => service.analyzePages(
          imageBytesList: [],
          vlmProvider: 'gemini',
          processingMode: ProcessingMode.textHeavy,
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('generateScript', () {
    test('posts vlm_output + language + llm_provider + keys and returns script', () async {
      final fakeScript = {
        'characters': [{'name': 'Narrator', 'voice': 'alloy'}],
        'lines': <dynamic>[],
      };
      final client = MockClient((request) async {
        expect(request.url.path, '/script');
        final body = jsonDecode(request.body) as Map;
        expect(body['language'], 'zh');
        expect(body['openai_api_key'], 'test-openai-key');
        expect(body['google_api_key'], 'test-google-key');
        return http.Response(
          jsonEncode({'script': fakeScript}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = makeService(client);
      final result = await service.generateScript(
        vlmOutput: [{'page': 1, 'text': 'Hello'}],
        language: 'zh',
        llmProvider: 'gpt4o',
      );
      expect(result['characters'], isNotEmpty);
    });

    test('throws ApiException on error', () async {
      final client = MockClient((_) async => http.Response('bad', 500));
      final service = makeService(client);
      await expectLater(
        () => service.generateScript(vlmOutput: [], language: 'en', llmProvider: 'gpt4o'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('generateAudio', () {
    test('posts lines + openai_api_key and returns audio results', () async {
      final fakeResults = [
        {'index': 0, 'status': 'ready', 'audio_b64': base64Encode([1, 2, 3])}
      ];
      final client = MockClient((request) async {
        expect(request.url.path, '/tts');
        final body = jsonDecode(request.body) as Map;
        expect(body['lines'], isNotEmpty);
        expect(body['openai_api_key'], 'test-openai-key');
        return http.Response(
          jsonEncode(fakeResults),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = makeService(client);
      final result = await service.generateAudio(lines: [
        {'index': 0, 'text': 'Hi', 'voice': 'alloy'}
      ]);
      expect(result.first['status'], 'ready');
    });
  });
}
```

- [ ] **Step 2: Run Flutter tests — expect compile error**

```bash
flutter test test/services/api_service_test.dart
```
Expected: compile error — `ApiService` doesn't have `openAiKey`/`googleKey` yet.

- [ ] **Step 3: Update `api_service.dart`**

Replace the entire file `lib/services/api_service.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/processing_mode.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  final String baseUrl;
  final String openAiKey;
  final String googleKey;
  final http.Client client;

  ApiService({
    required this.baseUrl,
    required this.openAiKey,
    required this.googleKey,
    http.Client? client,
  }) : client = client ?? http.Client();

  Future<List<Map<String, dynamic>>> analyzePages({
    required List<Uint8List> imageBytesList,
    required String vlmProvider,
    required ProcessingMode processingMode,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/analyze'))
      ..fields['vlm_provider'] = vlmProvider
      ..fields['processing_mode'] = processingMode.toApiValue()
      ..fields['openai_api_key'] = openAiKey
      ..fields['google_api_key'] = googleKey;
    for (int i = 0; i < imageBytesList.length; i++) {
      request.files.add(http.MultipartFile.fromBytes(
        'images',
        imageBytesList[i],
        filename: 'page_${i + 1}.jpg',
      ));
    }
    final streamed = await client.send(request);
    final response = await http.Response.fromStream(streamed);
    _checkStatus(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['pages'] as List);
  }

  Future<Map<String, dynamic>> generateScript({
    required List<Map<String, dynamic>> vlmOutput,
    required String language,
    required String llmProvider,
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/script'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'vlm_output': vlmOutput,
        'language': language,
        'llm_provider': llmProvider,
        'openai_api_key': openAiKey,
        'google_api_key': googleKey,
      }),
    );
    _checkStatus(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data['script'] as Map);
  }

  Future<List<Map<String, dynamic>>> generateAudio({
    required List<Map<String, dynamic>> lines,
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/tts'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'lines': lines,
        'openai_api_key': openAiKey,
      }),
    );
    _checkStatus(response);
    final data = jsonDecode(response.body) as List;
    return List<Map<String, dynamic>>.from(data);
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }
}
```

- [ ] **Step 4: Fix `_RecordingApiService` super constructor in `loading_screen_live_test.dart`**

In `test/screens/loading_screen_live_test.dart`, find line 18:
```dart
_RecordingApiService() : super(baseUrl: 'http://fake');
```
Change it to:
```dart
_RecordingApiService() : super(baseUrl: 'http://fake', openAiKey: 'test', googleKey: 'test');
```

- [ ] **Step 5: Run all Flutter tests — expect pass**

```bash
flutter test
```
Expected: all 54 tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/services/api_service.dart test/services/api_service_test.dart test/screens/loading_screen_live_test.dart
git commit -m "feat: add openAiKey/googleKey to ApiService, send in all request bodies"
```

---

## Task 5: Flutter — SettingsService + pubspec

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/services/settings_service.dart`

No automated tests for `SettingsService` (thin wrapper around a platform API — testing requires OS credential store integration which is out of scope).

- [ ] **Step 1: Add `flutter_secure_storage` to `pubspec.yaml`**

In `pubspec.yaml`, add under `dependencies:` (after `crypto`):
```yaml
  flutter_secure_storage: ^9.0.0
```

- [ ] **Step 2: Fetch dependency**

```bash
flutter pub get
```
Expected: resolves successfully.

- [ ] **Step 3: Create `lib/services/settings_service.dart`**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsService {
  static const _openAiKey = 'openai_api_key';
  static const _googleKey = 'google_api_key';

  final FlutterSecureStorage _storage;

  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<bool> hasKeys() async {
    final openAi = await _storage.read(key: _openAiKey);
    final google = await _storage.read(key: _googleKey);
    return openAi != null &&
        openAi.isNotEmpty &&
        google != null &&
        google.isNotEmpty;
  }

  Future<({String openAi, String google})> getKeys() async {
    final openAi = await _storage.read(key: _openAiKey) ?? '';
    final google = await _storage.read(key: _googleKey) ?? '';
    return (openAi: openAi, google: google);
  }

  Future<void> saveKeys({
    required String openAiKey,
    required String googleKey,
  }) async {
    await _storage.write(key: _openAiKey, value: openAiKey);
    await _storage.write(key: _googleKey, value: googleKey);
  }

  Future<void> clearKeys() async {
    await _storage.delete(key: _openAiKey);
    await _storage.delete(key: _googleKey);
  }
}
```

- [ ] **Step 4: Run flutter analyze**

```bash
flutter analyze lib/services/settings_service.dart
```
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/services/settings_service.dart
git commit -m "feat: add SettingsService with flutter_secure_storage"
```

---

## Task 6: Flutter — Settings providers

**Files:**
- Create: `lib/providers/settings_provider.dart`

- [ ] **Step 1: Create `lib/providers/settings_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';
import '../services/api_service.dart';

/// Singleton SettingsService instance.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

/// Loads both API keys from secure storage.
/// Invalidate this after saveKeys() to rebuild apiServiceProvider.
final apiKeysProvider =
    FutureProvider<({String openAi, String google})>((ref) async {
  return ref.read(settingsServiceProvider).getKeys();
});

/// Builds ApiService pre-loaded with the saved API keys.
final apiServiceProvider = FutureProvider<ApiService>((ref) async {
  final keys = await ref.watch(apiKeysProvider.future);
  return ApiService(
    baseUrl: 'http://localhost:8000',
    openAiKey: keys.openAi,
    googleKey: keys.google,
  );
});

/// Initial GoRouter location — overridden in main.dart based on hasKeys().
final initialLocationProvider = Provider<String>((_) => '/');
```

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze lib/providers/settings_provider.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/providers/settings_provider.dart
git commit -m "feat: add settings Riverpod providers"
```

---

## Task 7: Flutter — Settings screen UI

**Files:**
- Create: `lib/screens/settings_screen.dart`

No automated widget tests (deferred per spec).

- [ ] **Step 1: Create `lib/screens/settings_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _openAiController = TextEditingController();
  final _googleController = TextEditingController();
  bool _showOpenAi = false;
  bool _showGoogle = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingKeys();
  }

  Future<void> _loadExistingKeys() async {
    final keys = await ref.read(settingsServiceProvider).getKeys();
    if (!mounted) return;
    _openAiController.text = keys.openAi;
    _googleController.text = keys.google;
    setState(() {}); // Recompute canSave so Save button enables when keys are pre-filled.
  }

  @override
  void dispose() {
    _openAiController.dispose();
    _googleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(settingsServiceProvider).saveKeys(
            openAiKey: _openAiController.text.trim(),
            googleKey: _googleController.text.trim(),
          );
      ref.invalidate(apiKeysProvider);
      if (!mounted) return;
      // Use canPop() to detect first launch (no back stack) vs gear-icon open.
      // On first launch, initialLocation is '/settings' with no prior route.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save keys. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _openAiController.text.trim().isNotEmpty &&
        _googleController.text.trim().isNotEmpty;
    // Hide back button when there is nowhere to go back to (first launch).
    final hasBackStack = context.canPop();

    return Scaffold(
      appBar: AppBar(
        title: const Text('API Keys'),
        automaticallyImplyLeading: hasBackStack,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (!hasBackStack) ...[
            const Text(
              'Enter your API keys to get started.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
          ],
          TextField(
            controller: _openAiController,
            obscureText: !_showOpenAi,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'OpenAI API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showOpenAi ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showOpenAi = !_showOpenAi),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _googleController,
            obscureText: !_showGoogle,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Google API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showGoogle ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showGoogle = !_showGoogle),
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: (canSave && !_saving) ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze lib/screens/settings_screen.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat: add Settings screen UI"
```

---

## Task 8: Flutter — Navigation wiring (main.dart, app.dart, library gear)

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app.dart`
- Modify: `lib/screens/library_screen.dart`

- [ ] **Step 1: Update `lib/main.dart`**

Replace the entire file:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'app.dart';
import 'db/database.dart';
import 'mock/mock_data.dart';
import 'providers/settings_provider.dart';
import 'services/settings_service.dart';

Future<void> _seedMockData() async {
  final db = AppDatabase.instance;
  final existing = await db.getBook('mock_book_001');
  if (existing != null) return;
  await db.insertBook(createMockBook());
  await db.insertAudioVersion(createMockAudioVersion());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await _seedMockData();

  // Determine initial route before building the widget tree.
  // SettingsService() is constructed once here — safe because flutter_secure_storage
  // has no in-memory state; both this instance and the one in settingsServiceProvider
  // read from the same OS credential store.
  final hasKeys = await SettingsService().hasKeys();

  runApp(ProviderScope(
    overrides: [
      initialLocationProvider.overrideWithValue(hasKeys ? '/' : '/settings'),
    ],
    child: const BookActorApp(),
  ));
}
```

- [ ] **Step 2: Update `lib/app.dart`**

Replace the entire file:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/settings_provider.dart';
import 'screens/library_screen.dart';
import 'screens/book_detail_screen.dart';
import 'screens/upload_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/player_screen.dart';
import 'screens/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final initialLocation = ref.watch(initialLocationProvider);
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
      GoRoute(
        path: '/book/:bookId',
        builder: (_, state) =>
            BookDetailScreen(bookId: state.pathParameters['bookId']!),
      ),
      GoRoute(path: '/upload', builder: (_, __) => const UploadScreen()),
      GoRoute(
        path: '/loading',
        builder: (context, state) {
          final extra = state.extra as LoadingParams?;
          return LoadingScreen(
            bookId: extra?.bookId ?? '',
            language: extra?.language ?? 'en',
            params: extra,
          );
        },
      ),
      GoRoute(
        path: '/loading/:bookId/:language',
        builder: (_, state) => LoadingScreen(
          bookId: state.pathParameters['bookId']!,
          language: state.pathParameters['language']!,
        ),
      ),
      GoRoute(
        path: '/player/:versionId',
        builder: (_, state) =>
            PlayerScreen(versionId: state.pathParameters['versionId']!),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
    ],
  );
});

class BookActorApp extends ConsumerWidget {
  const BookActorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'BookActor',
      routerConfig: router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
        useMaterial3: true,
      ),
    );
  }
}
```

- [ ] **Step 3: Add gear icon to `LibraryScreen` AppBar**

In `lib/screens/library_screen.dart`, find the `AppBar` line:
```dart
appBar: AppBar(title: const Text('My Books')),
```
Replace with:
```dart
appBar: AppBar(
  title: const Text('My Books'),
  actions: [
    IconButton(
      icon: const Icon(Icons.settings),
      onPressed: () => context.push('/settings'),
      tooltip: 'API Keys',
    ),
  ],
),
```

- [ ] **Step 4: Run flutter analyze**

```bash
flutter analyze lib/main.dart lib/app.dart lib/screens/library_screen.dart
```
Expected: no errors.

- [ ] **Step 5: Run full test suite**

```bash
flutter test
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/app.dart lib/screens/library_screen.dart
git commit -m "feat: add settings navigation, first-launch redirect, gear icon in library"
```

---

## Task 9: Flutter — LoadingScreen ConsumerStatefulWidget migration

**Files:**
- Modify: `lib/screens/loading_screen.dart`

- [ ] **Step 1: Update `LoadingScreen` to `ConsumerStatefulWidget`**

In `lib/screens/loading_screen.dart`:

1. Add import at the top:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
```

2. Change class declaration from:
```dart
class LoadingScreen extends StatefulWidget {
```
to:
```dart
class LoadingScreen extends ConsumerStatefulWidget {
```

3. Change state class declaration from:
```dart
class _LoadingScreenState extends State<LoadingScreen> {
```
to:
```dart
class _LoadingScreenState extends ConsumerState<LoadingScreen> {
```

4. In `_runLivePipeline()`, find the line:
```dart
final api = widget.apiService ?? ApiService(baseUrl: 'http://localhost:8000');
```
Replace with:
```dart
final api = widget.apiService ?? await ref.read(apiServiceProvider.future);
```

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze lib/screens/loading_screen.dart
```
Expected: no errors.

- [ ] **Step 3: Run full test suite**

```bash
flutter test
```
Expected: all tests pass (the `loading_screen_live_test.dart` passes `apiService: fakeApi` via constructor — the widget injection path is unaffected by the Riverpod migration).

- [ ] **Step 4: Commit**

```bash
git add lib/screens/loading_screen.dart
git commit -m "feat: LoadingScreen resolves ApiService via Riverpod provider"
```

---

## Task 10: Flutter — UploadScreen keys guard + hint text

**Files:**
- Modify: `lib/screens/upload_screen.dart`

- [ ] **Step 1: Add `apiKeysProvider` watch and update Generate button**

In `lib/screens/upload_screen.dart`:

1. Add import at the top:
```dart
import '../providers/settings_provider.dart';
```

2. In the `build()` method, before the `return Scaffold(...)`, add:
```dart
final keysAsync = ref.watch(apiKeysProvider);
final hasApiKeys = keysAsync.valueOrNull != null &&
    keysAsync.valueOrNull!.openAi.isNotEmpty &&
    keysAsync.valueOrNull!.google.isNotEmpty;
```

3. Find the existing Generate button block:
```dart
FilledButton.icon(
  onPressed: (_selectedFilePath == null || _processingMode == null || _isGenerating)
      ? null
      : _generate,
  icon: const Icon(Icons.auto_awesome),
  label: const Text('Generate Audiobook'),
),
```
Replace it (updating `onPressed` and appending the hint text in one edit):
```dart
FilledButton.icon(
  onPressed: (!hasApiKeys || _selectedFilePath == null || _processingMode == null || _isGenerating)
      ? null
      : _generate,
  icon: const Icon(Icons.auto_awesome),
  label: const Text('Generate Audiobook'),
),
if (!hasApiKeys) ...[
  const SizedBox(height: 8),
  Text(
    'Add API keys in Settings to generate.',
    style: Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.error),
    textAlign: TextAlign.center,
  ),
],
```

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze lib/screens/upload_screen.dart
```
Expected: no errors.

- [ ] **Step 3: Run full test suite**

```bash
flutter test
```
Expected: all tests pass.

- [ ] **Step 4: Manual smoke test**

Run the app (`flutter run -d windows`):
1. On first launch (no keys saved): app opens at Settings screen, back button hidden
2. Enter both keys, tap Save → navigates to library
3. Tap gear icon → Settings screen opens with keys pre-filled, back button visible
4. Go to upload → if keys saved, Generate button enabled (when file + mode also selected)
5. Clear a key → Save → go to upload → Generate button disabled + hint text visible

- [ ] **Step 5: Commit**

```bash
git add lib/screens/upload_screen.dart
git commit -m "feat: add API keys guard to Generate button with hint text"
```

---

## Final check

- [ ] **Run full Flutter test suite**

```bash
flutter test
```
Expected: all tests pass.

- [ ] **Run full Python test suite**

```bash
cd D:/developer_tools/bookactor
python -m pytest -v
```
Expected: all backend tests pass.
