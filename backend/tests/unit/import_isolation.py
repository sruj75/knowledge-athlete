"""Small shared helpers for unit tests that temporarily stub import modules."""

from __future__ import annotations

import hashlib
import sys
import types
import uuid
from types import ModuleType
from typing import Iterable, Mapping
from unittest.mock import MagicMock


class AutoMockModule(ModuleType):
    """Import-complete stub whose missing attributes resolve to isolated mocks."""

    def __getattr__(self, name: str):
        if name.startswith("__") and name.endswith("__"):
            raise AttributeError(name)
        mock = MagicMock()
        setattr(self, name, mock)
        return mock


def snapshot_sys_modules(names: Iterable[str]) -> dict[str, ModuleType | None]:
    return {name: sys.modules.get(name) for name in names}


def restore_sys_modules(saved: Mapping[str, ModuleType | None]) -> None:
    for name, original in saved.items():
        current = sys.modules.get(name)
        if original is None:
            removed = sys.modules.pop(name, None)
            if "." in name:
                parent_name, child_name = name.rsplit(".", 1)
                parent = sys.modules.get(parent_name)
                if (
                    isinstance(parent, ModuleType)
                    and hasattr(parent, child_name)
                    and getattr(parent, child_name, None) is (removed or current)
                ):
                    delattr(parent, child_name)
        else:
            sys.modules[name] = original
            if "." in name:
                parent_name, child_name = name.rsplit(".", 1)
                parent = sys.modules.get(parent_name)
                if isinstance(parent, ModuleType):
                    setattr(parent, child_name, original)


def install_database_client_stub() -> ModuleType:
    client = types.ModuleType("database._client")
    client.db = MagicMock()
    client.delete_collection_recursive = MagicMock()
    client.get_firestore_client = lambda: client.db

    def document_id_from_seed(seed: str) -> str:
        digest = hashlib.sha256(seed.encode("utf-8")).digest()
        return str(uuid.UUID(bytes=digest[:16], version=4))

    client.document_id_from_seed = document_id_from_seed
    sys.modules["database._client"] = client
    database_package = sys.modules.get("database")
    if isinstance(database_package, ModuleType):
        setattr(database_package, "_client", client)
    return client
