import base64
import json
import litellm

_VLM_MODELS = {
    "gemini": "gemini/gemini-2.5-pro",
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

_USER_PROMPTS = {
    "text_heavy": "Extract the story text from every page.",
    "picture_book": "Describe the illustrations and story for every page.",
}

_VLM_KEY_SOURCE = {
    "gpt4o": "openai",
    "gemini": "google",
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
    key_source = _VLM_KEY_SOURCE.get(vlm_provider, "google")
    api_key = openai_api_key if key_source == "openai" else google_api_key

    image_content = []
    for img_bytes in image_bytes_list:
        b64 = base64.b64encode(img_bytes).decode()
        image_content.append({
            "type": "image_url",
            "image_url": {"url": f"data:image/jpeg;base64,{b64}"},
        })
    user_text = _USER_PROMPTS.get(processing_mode, _USER_PROMPTS["text_heavy"])
    image_content.append({"type": "text", "text": user_text})

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
