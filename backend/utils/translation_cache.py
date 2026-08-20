"""Material-change policy for transient translations."""

from typing import Optional


def _normalize_base_language(language: Optional[str]) -> Optional[str]:
    if not language:
        return None
    return language.split('-')[0].lower()


def should_emit_translation(
    source_text: str,
    translated_text: str,
    detected_lang: Optional[str],
    target_language: Optional[str],
) -> bool:
    """Return whether a translation changes what the user would read."""

    normalized_source = " ".join(source_text.split())
    normalized_translated = " ".join((translated_text or "").split())
    if normalized_source != normalized_translated:
        return True

    detected_base = _normalize_base_language(detected_lang)
    target_base = _normalize_base_language(target_language)
    if detected_base and target_base and detected_base == target_base:
        return False
    return False
