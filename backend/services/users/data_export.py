from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Iterable, Iterator, Mapping, Sequence, cast

from database import chat as chat_db
from database import conversations as conversations_db
from database.users import get_people, get_user_profile

JsonRecord = dict[str, Any]
_PROFILE_EXPORT_EXCLUDED_FIELDS = frozenset({'name'})


def _exportable_profile(profile: JsonRecord | None) -> JsonRecord:
    if not profile:
        return {}
    return {key: value for key, value in profile.items() if key not in _PROFILE_EXPORT_EXCLUDED_FIELDS}


def _json_default(obj: object) -> str:
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")


def iter_user_data_export(uid: str) -> Iterator[str]:
    yield '{\n'

    profile = _exportable_profile(cast(JsonRecord | None, get_user_profile(uid)))
    yield '  "profile": ' + json.dumps(profile, default=_json_default, indent=2) + ',\n'

    yield '  "conversations": [\n'
    first = True
    for conv in conversations_db.iter_all_conversations(uid, include_discarded=True):
        if conv is None:
            continue
        if not first:
            yield ',\n'
        first = False
        yield '    ' + json.dumps(conv, default=_json_default, indent=4)
    yield '\n  ],\n'

    people = cast(Sequence[Mapping[str, Any]], get_people(uid))
    yield '  "people": ' + json.dumps(people, default=_json_default, indent=2) + ',\n'

    yield '  "chat_messages": [\n'
    first = True
    for msg in cast(Iterable[Mapping[str, Any]], chat_db.iter_all_messages(uid)):
        if not first:
            yield ',\n'
        first = False
        yield '    ' + json.dumps(msg, default=_json_default, indent=4)
    yield '\n  ]\n'

    yield '}\n'
