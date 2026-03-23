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
