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
    prompt = (
        "You are a children's audiobook script writer. Given the extracted story text from a "
        "picture book, output ONLY a JSON object (no markdown fences) with this exact structure:\n"
        f'{{"characters": [{{"name": "...", "voice": "<{voices}>", "traits": "..."}}], '
        '"chunks": [{"index": <0-based int>, "text": "...", "speakers": ["..."], '
        '"duration_ms": 0, "status": "pending"}]}\n'
        "Rules:\n"
        "- Narrator is always present. Assign each character a distinct voice. "
        "Never change a character's voice mid-story.\n"
        "- Group the full story into sequential dialogue passages. Each chunk's 'text' field "
        "must not exceed 3500 bytes when UTF-8 encoded. "
        "For Latin-script languages (English, French, German, etc.) this allows roughly 2000–3000 characters. "
        "For CJK scripts (Chinese, Japanese, Korean) limit to roughly 800–1000 characters per chunk.\n"
        "- Format 'text' as lines of 'Character: utterance\\n' — each Character name exactly "
        "matching a name in the 'characters' array.\n"
        "- Never cut mid-sentence. Chunks end at natural pause points.\n"
        "- 'speakers' lists every character name that appears in that chunk's text.\n"
        "- Narrator and characters flow naturally together.\n"
        "- 'duration_ms' is always 0.\n"
        "- LANGUAGE RULE: Only the 'text' field inside each chunk must be written in "
        "the language specified by the user. All other fields — character names, traits, "
        "voice names, speakers lists, and all keys — must remain in English.\n"
        "- Character names in the 'text' field must be the same English names as in 'characters'.\n"
        "- Every character must have a UNIQUE voice — never assign the same voice to two characters.\n"
    )
    if tts_provider == "qwen":
        return (
            "You are a children's audiobook script writer. Given the extracted story text from a "
            "picture book, output ONLY a JSON object (no markdown fences) with this exact structure:\n"
            '{"characters": [{"name": "...", "voice_prompt": "<description>", "voice_id": null}], '
            '"chunks": [{"index": <0-based int>, "text": "...", "speakers": ["..."], '
            '"duration_ms": 0, "status": "pending"}]}\n'
            "Rules:\n"
            "- Narrator is always present.\n"
            "- Group the full story into sequential dialogue passages. Each chunk's 'text' field "
            "must not exceed 3500 bytes when UTF-8 encoded. "
            "For Latin-script languages (English, French, German, etc.) this allows roughly "
            "2000\u20133000 characters. "
            "For CJK scripts (Chinese, Japanese, Korean) limit to roughly 800\u20131000 characters per chunk.\n"
            "- Format 'text' as lines of 'Character: utterance\\n' \u2014 each Character name exactly "
            "matching a name in the 'characters' array.\n"
            "- Never cut mid-sentence. Chunks end at natural pause points.\n"
            "- 'speakers' lists every character name that appears in that chunk's text.\n"
            "- Narrator and characters flow naturally together.\n"
            "- 'duration_ms' is always 0.\n"
            "- LANGUAGE RULE: Only the 'text' field inside each chunk must be written in "
            "the language specified by the user. All other fields \u2014 character names, speakers lists, "
            "and all keys \u2014 must remain in English.\n"
            "- Character names in the 'text' field must be the same English names as in 'characters'.\n"
            "- Every character must have a UNIQUE voice_prompt.\n"
            "- Always set voice_id to JSON null.\n"
            "- voice_prompt: describe age, gender, pitch, speed, emotion, characteristics, and role "
            "context. Be specific and multi-dimensional. Avoid vague terms like 'nice' or 'normal'. "
            "Example: 'A cheerful 8-year-old girl, bright high-pitched voice, fast-paced speech, "
            "excited and curious, sweet and childlike, suitable for children animation.'\n"
        )
    if tts_provider == "gemini":
        prompt += "- Female voices: Aoede, Kore, Zephyr, Leda. Male voices: Charon, Fenrir, Puck, Orus.\n"
    prompt += (
        "- Use gender contrast: if Narrator uses a female voice, assign male voices to male "
        "characters and vice versa. Mix genders across characters for the best listening experience.\n"
        f"- Voice names must use title case: {voices}."
    )
    return prompt

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
