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
