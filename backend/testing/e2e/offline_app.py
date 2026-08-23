"""Offline-only ASGI factories with hermetic provider boundaries."""

from __future__ import annotations

from typing import Any


def backend_app() -> Any:
    """Build the regular backend app after installing offline provider fakes."""

    from testing.e2e.fakes.conversation_compute import install_offline_conversation_compute_fakes
    from testing.e2e.fakes.stt import install_offline_managed_stt_fake

    install_offline_conversation_compute_fakes()
    install_offline_managed_stt_fake()
    from main import app

    return app


def desktop_backend_app() -> Any:
    """Build the desktop backend after installing offline provider fakes."""

    from testing.e2e.fakes.conversation_compute import install_offline_conversation_compute_fakes
    from testing.e2e.fakes.stt import install_offline_managed_stt_fake

    install_offline_conversation_compute_fakes()
    install_offline_managed_stt_fake()
    from desktop_backend import app

    return app
