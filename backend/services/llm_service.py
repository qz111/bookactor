import json
import re
import litellm


def _strip_fences(text: str) -> str:
    """Remove leading/trailing markdown code fences if present."""
    return re.sub(r"^```(?:json)?\s*|\s*```$", "", text.strip(), flags=re.DOTALL)

_LLM_MODELS = {
    "gemini": "gemini/gemini-2.5-pro",
    "gpt4o": "gpt-4o",
}

_LLM_KEY_SOURCE = {
    "gpt4o": "openai",
    "gemini": "google",
}

_VOICES = {
    "openai": "alloy|echo|fable|onyx|nova|shimmer",
    "gemini": "aoede|charon|fenrir|kore|puck|zephyr|leda|orus",
}

def _system_prompt(tts_provider: str) -> str:
    voices = _VOICES.get(tts_provider, _VOICES["openai"])
    return (
        "You are a children's audiobook script writer. Given the extracted story text from a "
        "picture book, output ONLY a JSON object (no markdown fences) with this exact structure:\n"
        f'{{"characters": [{{"name": "...", "voice": "<{voices}>", '
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
    tts_provider: str,
    openai_api_key: str,
    google_api_key: str,
) -> dict:
    """Call LLM to generate a structured script; retry once on malformed JSON."""
    model = _LLM_MODELS.get(llm_provider)
    if model is None:
        raise ValueError(f"Unknown llm_provider: {llm_provider!r}")

    key_source = _LLM_KEY_SOURCE.get(llm_provider, "google")
    api_key = openai_api_key if key_source == "openai" else google_api_key

    user_content = (
        f"Language: {language}\n\n"
        f"Extracted story pages:\n{json.dumps(vlm_output, ensure_ascii=False)}"
    )

    base_prompt = _system_prompt(tts_provider)
    for attempt in range(2):
        system = base_prompt + (_STRICT_ADDENDUM if attempt == 1 else "")
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
            data = json.loads(_strip_fences(raw))
            for line in data.get("lines", []):
                line["status"] = "pending"
            return data
        except (json.JSONDecodeError, KeyError) as exc:
            if attempt == 1:
                raise ValueError(f"LLM returned invalid JSON: {raw!r}") from exc

    raise ValueError("LLM returned invalid JSON after 2 attempts")
