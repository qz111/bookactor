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
    "gemini": "Aoede|Charon|Fenrir|Kore|Puck|Zephyr|Leda|Orus",
}

def _system_prompt(tts_provider: str) -> str:
    voices = _VOICES.get(tts_provider, _VOICES["openai"])
    return (
        "You are a children's audiobook script writer. Given the extracted story text from a "
        "picture book, output ONLY a JSON object (no markdown fences) with this exact structure:\n"
        f'{{"characters": [{{"name": "...", "voice": "<{voices}>", "traits": "..."}}], '
        '"chunks": [{"index": <0-based int>, "text": "...", "speakers": ["..."], '
        '"duration_ms": 0, "status": "pending"}]}\n'
        "Rules:\n"
        "- Narrator is always present. Assign each character a distinct voice. "
        "Never change a character's voice mid-story.\n"
        "- Group the full story into sequential dialogue passages. Each chunk's 'text' field "
        "must be between 2000 and 3000 characters.\n"
        "- Format 'text' as lines of 'Character: utterance\\n' — each Character name exactly "
        "matching a name in the 'characters' array.\n"
        "- Never cut mid-sentence. Chunks end at natural pause points.\n"
        "- 'speakers' lists every character name that appears in that chunk's text.\n"
        "- Narrator and characters flow naturally together.\n"
        "- 'duration_ms' is always 0.\n"
        "- All dialogue text must be in the language specified by the user.\n"
        f"- Voice names must use title case: {voices}."
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
            for chunk in data.get("chunks", []):
                chunk["status"] = "pending"
            return data
        except (json.JSONDecodeError, KeyError) as exc:
            if attempt == 1:
                raise ValueError(f"LLM returned invalid JSON: {raw!r}") from exc

    raise ValueError("LLM returned invalid JSON after 2 attempts")
