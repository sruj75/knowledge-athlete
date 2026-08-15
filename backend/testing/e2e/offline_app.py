"""Offline-only ASGI factories with hermetic managed-STT boundaries."""

from __future__ import annotations

from typing import Any


def backend_app() -> Any:
    """Build the regular backend app after installing the offline STT fake."""

    from testing.e2e.fakes.stt import install_offline_managed_stt_fake

    install_offline_managed_stt_fake()
    from main import app

    return app


def desktop_backend_app() -> Any:
    """Build the desktop backend after installing the offline STT fake."""

    from testing.e2e.fakes.stt import install_offline_managed_stt_fake

    install_offline_managed_stt_fake()
    from desktop_backend import app

    return app
