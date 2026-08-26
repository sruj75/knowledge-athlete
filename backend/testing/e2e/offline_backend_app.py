"""Canonical backend ASGI app with hermetic provider boundaries installed."""

from testing.e2e.fakes.conversation_compute import install_offline_conversation_compute_fakes
from testing.e2e.fakes.managed_stt_install import install_offline_managed_stt_fake

install_offline_conversation_compute_fakes()
install_offline_managed_stt_fake()

# The fakes must be installed before route modules bind their collaborators.
from main import app  # noqa: E402
