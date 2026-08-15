"""
Tools for answering questions about the Omi/Friend product.
"""

import os

import httpx
from langchain_core.tools import tool  # type: ignore[reportUnknownVariableType]  # langchain @tool decorator partially typed
from database.redis_db import get_generic_cache, set_generic_cache
import logging

logger = logging.getLogger(__name__)


def get_github_docs_content(repo: str = "BasedHardware/omi", path: str = "docs/doc") -> dict[str, str]:
    """Read product documentation without depending on the retired app runtime."""
    cache_key = f'get_github_docs_content_{repo}_{path}'
    if cached := get_generic_cache(cache_key):
        return cached
    docs_content: dict[str, str] = {}
    headers = {"Authorization": f"token {os.getenv('GITHUB_TOKEN')}"}

    def get_contents(current_path: str) -> None:
        response = httpx.get(
            f"https://api.github.com/repos/{repo}/contents/{current_path}", headers=headers, timeout=30.0
        )
        if response.status_code != 200:
            logger.error("Failed to fetch product docs path=%s status=%s", current_path, response.status_code)
            return
        contents = response.json()
        if not isinstance(contents, list):
            return
        for item in contents:
            if item["type"] == "file" and item["name"].endswith((".md", ".mdx")):
                raw_response = httpx.get(item["download_url"], headers=headers, timeout=30.0)
                if raw_response.status_code == 200:
                    docs_content[item["path"]] = raw_response.text
            elif item["type"] == "dir":
                get_contents(item["path"])

    get_contents(path)
    set_generic_cache(cache_key, docs_content, 60 * 24 * 7)
    return docs_content


@tool
def get_omi_product_info_tool(query: str) -> str:
    """
    Get information about the Omi/Friend product to answer questions about features, functionality, setup, or purchasing.

    Use this tool when the user asks about:
    - How Omi/Friend works
    - What features the app has
    - How to set up or use Omi
    - Plans and pricing information
    - App capabilities and functionality
    - Troubleshooting product issues

    DO NOT use this tool for:
    - Questions about the user's personal conversations or memories
    - Questions about what the user said or did
    - Action items or reminders
    - Personal data queries

    Args:
        query: The specific question about Omi/Friend (e.g., "How does conversation capture work?", "Which plans are available?")

    Returns:
        Product documentation content from GitHub that can help answer the question

    Example:
        query="How do I start a conversation recording?"
        Returns documentation about app setup and conversation capture
    """
    # Fetch the product docs. A network or GitHub API failure must not break the chat turn, so fail
    # soft with an "Error: ..." string like the other retrieval tools instead of letting the
    # exception escape into the agent loop.
    try:
        context = get_github_docs_content()
    except Exception as e:
        logger.warning(f"get_omi_product_info_tool - failed to fetch product docs: {e}")
        return (
            "Error: the Omi product documentation could not be retrieved right now. Tell the user "
            "that product information is temporarily unavailable and to try again in a little while."
        )

    if not context:
        # An empty result (e.g. the GitHub API returned non-200) would otherwise produce a docs
        # string with no real content, which misleads the model into answering from nothing. Log it
        # so a silent "no docs" state is diagnosable in prod, not only visible to the user.
        logger.warning("get_omi_product_info_tool - product docs fetch returned no content")
        return (
            "No Omi product documentation is available right now. Tell the user that product "
            "information is temporarily unavailable and to try again in a little while."
        )

    # Format context as a comprehensive documentation string
    context_str = 'Omi/Friend Product Documentation:\n\n'
    for section, content in context.items():
        context_str += f'## {section}\n\n{content}\n\n'

    context_str += (
        '\n\nUse this documentation to answer questions about the Omi/Friend product, its features, setup, and usage.'
    )

    return context_str
