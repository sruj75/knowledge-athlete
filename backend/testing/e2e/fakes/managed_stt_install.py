"""Install the pure offline STT fake at production collaborator boundaries."""

import sys

from utils import analytics
from utils.stt import pre_recorded, streaming, vad_gate

from .stt import fake_process_audio_modulate, make_fake_prerecorded_provider


def install_offline_managed_stt_fake() -> None:
    """Install fake managed-STT boundaries before an offline ASGI app is imported."""

    streaming.process_audio_modulate = fake_process_audio_modulate
    pre_recorded.get_prerecorded_provider = make_fake_prerecorded_provider
    vad_gate.is_gate_enabled = lambda: False
    analytics.record_usage = lambda *args, **kwargs: None

    # Keep installation idempotent if a caller imported one of these modules
    # before selecting the offline app.
    already_loaded = {
        "routers.listen.receiver": {
            "process_audio_modulate": fake_process_audio_modulate,
            "is_gate_enabled": lambda: False,
        },
        "routers.listen.runtime": {"record_usage": lambda *args, **kwargs: None},
        "routers.chat": {"process_audio_modulate": fake_process_audio_modulate},
    }
    for module_name, replacements in already_loaded.items():
        module = sys.modules.get(module_name)
        if module is None:
            continue
        for name, replacement in replacements.items():
            setattr(module, name, replacement)
