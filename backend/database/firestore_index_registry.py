"""Repository-owned Firestore query and index requirements.

The Firebase manifest is generated from this registry.  Query specs are added
incrementally: a registered query spec both builds its production query and
declares the exact composite index that query needs.  Existing index-only
requirements remain explicit here until their callers are migrated.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Mapping


@dataclass(frozen=True)
class FirestoreIndexField:
    field_path: str
    order: str | None = None
    array_config: str | None = None

    def to_manifest(self) -> dict[str, str]:
        if self.order is not None:
            return {'fieldPath': self.field_path, 'order': self.order}
        if self.array_config is not None:
            return {'fieldPath': self.field_path, 'arrayConfig': self.array_config}
        raise ValueError(f'Firestore index field {self.field_path!r} needs order or array_config')


@dataclass(frozen=True)
class FirestoreIndexRequirement:
    identifier: str
    collection_group: str
    query_scope: str
    fields: tuple[FirestoreIndexField, ...]

    def to_manifest(self) -> dict[str, Any]:
        return {
            'collectionGroup': self.collection_group,
            'queryScope': self.query_scope,
            'fields': [field.to_manifest() for field in self.fields],
        }

    @property
    def signature(self) -> tuple[str, str, tuple[tuple[str, str], ...]]:
        return (
            self.collection_group,
            self.query_scope,
            tuple((field.field_path, field.order or field.array_config or '') for field in self.fields),
        )


@dataclass(frozen=True)
class FirestoreQueryFilter:
    field_path: str
    operator: str
    value_name: str


@dataclass(frozen=True)
class FirestoreQuerySpec:
    """A serving compound query and the index requirement derived from it."""

    identifier: str
    collection_group: str
    query_scope: str
    filters: tuple[FirestoreQueryFilter, ...]
    index_fields: tuple[FirestoreIndexField, ...]

    @property
    def index_requirement(self) -> FirestoreIndexRequirement:
        return FirestoreIndexRequirement(
            identifier=self.identifier,
            collection_group=self.collection_group,
            query_scope=self.query_scope,
            fields=self.index_fields,
        )

    @property
    def query_signature(self) -> tuple[str, str, tuple[tuple[str, str], ...]]:
        return (
            self.collection_group,
            self.query_scope,
            tuple((query_filter.field_path, query_filter.operator) for query_filter in self.filters),
        )

    def build(
        self,
        collection: Any,
        values: Mapping[str, Any],
        *,
        field_filter_factory: Callable[[str, str, Any], Any],
    ) -> Any:
        """Build the actual Firestore query from declared filters and values."""

        query = collection
        for query_filter in self.filters:
            try:
                value = values[query_filter.value_name]
            except KeyError as exc:
                raise ValueError(f'{self.identifier} requires {query_filter.value_name!r}') from exc
            query = query.where(filter=field_filter_factory(query_filter.field_path, query_filter.operator, value))
        return query


def _asc(field_path: str) -> FirestoreIndexField:
    return FirestoreIndexField(field_path, order='ASCENDING')


def _desc(field_path: str) -> FirestoreIndexField:
    return FirestoreIndexField(field_path, order='DESCENDING')


# These explicit requirements preserve the current deployed index set while
# callers migrate one compound serving query at a time into QUERY_SPECS.
INDEX_ONLY_REQUIREMENTS = (
    FirestoreIndexRequirement(
        'conversations_category_created',
        'conversations',
        'COLLECTION',
        (_asc('discarded'), _asc('status'), _asc('structured.category'), _desc('created_at'), _desc('__name__')),
    ),
)


STALE_IN_PROGRESS_CONVERSATIONS_QUERY = FirestoreQuerySpec(
    identifier='conversations_in_progress_by_finished_at',
    collection_group='conversations',
    query_scope='COLLECTION',
    filters=(FirestoreQueryFilter('status', '==', 'status'),),
    index_fields=(
        _asc('status'),
        _asc('finished_at'),
        _asc('__name__'),
    ),
)

STARRED_CHAT_SESSIONS_QUERY = FirestoreQuerySpec(
    identifier='chat_sessions_starred_by_updated_at',
    collection_group='chat_sessions',
    query_scope='COLLECTION',
    filters=(FirestoreQueryFilter('starred', '==', 'starred'),),
    index_fields=(
        _asc('starred'),
        _desc('updated_at'),
        _desc('__name__'),
    ),
)

QUERY_SPECS = (
    STALE_IN_PROGRESS_CONVERSATIONS_QUERY,
    STARRED_CHAT_SESSIONS_QUERY,
)
INDEX_REQUIREMENTS = (
    *INDEX_ONLY_REQUIREMENTS,
    *(
        spec.index_requirement
        for spec in QUERY_SPECS
        # Firestore manages one-field indexes (including document-ID ordering)
        # itself and rejects them in the composite-index manifest.
        if len([field for field in spec.index_fields if field.field_path != '__name__']) > 1
    ),
)


def firebase_index_manifest() -> dict[str, list[dict[str, Any]]]:
    """Return Firebase's canonical composite-index manifest deterministically."""

    signatures: set[tuple[str, str, tuple[tuple[str, str], ...]]] = set()
    indexes: list[dict[str, Any]] = []
    for requirement in INDEX_REQUIREMENTS:
        if requirement.signature in signatures:
            raise ValueError(f'duplicate Firestore index requirement: {requirement.identifier}')
        signatures.add(requirement.signature)
        indexes.append(requirement.to_manifest())
    return {'indexes': indexes, 'fieldOverrides': []}
