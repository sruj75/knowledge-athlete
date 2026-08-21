"""Narrow Firestore transaction fixture for ordering-sensitive unit tests.

This fixture models document-reference ``get(transaction=...)`` plus transaction
``create``, ``set``, and ``update``. It enforces Firestore's rule that every
transactional read must occur before the first transactional write.

It deliberately models only the single-field ``>=`` query used by the S-20
transactional enforcement core. Optional staged writes model commit/rollback
visibility and injected commit failure; retry and contention semantics remain
out of scope. Extend it only when an incident proves that another boundary
needs a hermetic guard.

As fixture-integrity policy, a transaction accepts references created by its
own ``StrictFirestore`` instance only. This prevents accidental mixing of
unrelated in-memory stores; it is not a claim about Firestore client identity.
"""

from __future__ import annotations

from copy import deepcopy
from threading import RLock
from typing import Any

from google.api_core.exceptions import AlreadyExists, FailedPrecondition


class ReadAfterWriteError(RuntimeError):
    """Raised when a transaction performs a read after staging a write."""


class ForeignTransactionError(ValueError):
    """Raised when fixture policy forbids mixing transaction and reference stores."""


class UnsupportedFirestoreOperationError(NotImplementedError):
    """Raised for a Firestore operation this narrow fixture does not model."""


_SUPPORTED_OPERATIONS = (
    'document get/create, transaction-bound document/query get, single-field >= query, ' 'transaction create/set/update'
)


class StrictFirestoreSnapshot:
    def __init__(self, data: dict[str, Any] | None, update_time: int = 0):
        self._data = deepcopy(data)
        self.exists = data is not None
        self.update_time = update_time

    def to_dict(self) -> dict[str, Any] | None:
        return deepcopy(self._data)


class StrictFirestoreDocument:
    def __init__(self, database: StrictFirestore, path: tuple[str, ...]):
        self._database = database
        self.path = path

    def collection(self, name: str) -> StrictFirestoreCollection:
        return StrictFirestoreCollection(self._database, (*self.path, name))

    def get(self, transaction: StrictFirestoreTransaction | None = None) -> StrictFirestoreSnapshot:
        if transaction is not None:
            transaction._assert_reference_belongs(self)
            transaction._assert_read_allowed()
        with self._database.lock:
            return StrictFirestoreSnapshot(
                self._database.rows.get(self.path),
                self._database.versions.get(self.path, 0),
            )

    def create(self, data: dict[str, Any]) -> None:
        with self._database.lock:
            if self.path in self._database.rows:
                raise AlreadyExists('document already exists')
            self._database.rows[self.path] = deepcopy(data)
            self._database.versions[self.path] = self._database.versions.get(self.path, 0) + 1

    def update(self, data: dict[str, Any], option: StrictFirestoreWriteOption | None = None) -> None:
        with self._database.lock:
            if self.path not in self._database.rows:
                raise FailedPrecondition('missing row')
            if option is not None and self._database.versions.get(self.path, 0) != option.last_update_time:
                raise FailedPrecondition('document changed after read')
            self._database.rows[self.path].update(deepcopy(data))
            self._database.versions[self.path] = self._database.versions.get(self.path, 0) + 1

    def delete(self, *args: Any, **kwargs: Any) -> None:
        raise UnsupportedFirestoreOperationError(f'StrictFirestore supports only {_SUPPORTED_OPERATIONS}')


class StrictFirestoreCollection:
    def __init__(self, database: StrictFirestore, path: tuple[str, ...]):
        self._database = database
        self._path = path

    def document(self, name: str) -> StrictFirestoreDocument:
        return StrictFirestoreDocument(self._database, (*self._path, name))

    def where(self, field_path: str, op_string: str, value: Any) -> StrictFirestoreQuery:
        if op_string != '>=':
            raise UnsupportedFirestoreOperationError(f'StrictFirestore supports only {_SUPPORTED_OPERATIONS}')
        return StrictFirestoreQuery(self._database, self._path, field_path, value)

    def stream(self, *args: Any, **kwargs: Any) -> None:
        raise UnsupportedFirestoreOperationError(f'StrictFirestore supports only {_SUPPORTED_OPERATIONS}')


class StrictFirestoreQuery:
    def __init__(
        self,
        database: StrictFirestore,
        collection_path: tuple[str, ...],
        field_path: str,
        lower_bound: Any,
    ):
        self._database = database
        self._collection_path = collection_path
        self._field_path = field_path
        self._lower_bound = lower_bound

    def get(self, transaction: StrictFirestoreTransaction | None = None) -> list[StrictFirestoreSnapshot]:
        if transaction is not None:
            if transaction._database is not self._database:
                raise ForeignTransactionError('Firestore transaction and query must belong to the same store')
            transaction._assert_read_allowed()
        expected_length = len(self._collection_path) + 1
        snapshots: list[StrictFirestoreSnapshot] = []
        for path, row in self._database.rows.items():
            if len(path) != expected_length or path[: len(self._collection_path)] != self._collection_path:
                continue
            candidate = row.get(self._field_path)
            if candidate is not None and candidate >= self._lower_bound:
                snapshots.append(StrictFirestoreSnapshot(row))
        return snapshots


class StrictFirestoreWriteOption:
    def __init__(self, last_update_time: int):
        self.last_update_time = last_update_time


class StrictFirestoreTransaction:
    def __init__(self, database: StrictFirestore, *, allow_reads_after_writes: bool = False):
        self._database = database
        self._allow_reads_after_writes = allow_reads_after_writes
        self.lock = database.lock
        self.creates: list[tuple[tuple[str, ...], dict[str, Any]]] = []
        self.sets: list[tuple[tuple[str, ...], dict[str, Any]]] = []
        self.updates: list[tuple[tuple[str, ...], dict[str, Any]]] = []
        self.has_written = False
        self._read_only = False
        self._max_attempts = 1
        self._id: bytes | None = None
        self._staged_operations: list[tuple[str, tuple[str, ...], dict[str, Any], bool]] = []

    # The Firestore ``@transactional`` decorator drives these lifecycle hooks.
    # They deliberately keep this fixture single-attempt: it guards production
    # read-before-write ordering without pretending to model contention retries.
    def _clean_up(self) -> None:
        self._id = None
        self._staged_operations = []

    def _begin(self, retry_id: bytes | None = None) -> None:
        self._id = retry_id or b'strict-firestore-transaction'

    def _commit(self) -> list[Any]:
        if not self._database._stage_transaction_writes:
            self._clean_up()
            return []
        if self._database._fail_transaction_commit:
            raise RuntimeError('injected Firestore transaction commit failure')

        with self._database.lock:
            rows = deepcopy(self._database.rows)
            versions = deepcopy(self._database.versions)
            for operation, path, payload, merge in self._staged_operations:
                if operation == 'create' and path in rows:
                    raise RuntimeError('document already exists')
                if operation == 'update' and path not in rows:
                    raise RuntimeError('missing row')
                if operation == 'set' and merge:
                    rows.setdefault(path, {}).update(payload)
                elif operation == 'update':
                    rows[path].update(payload)
                else:
                    rows[path] = payload
                versions[path] = versions.get(path, 0) + 1
            self._database.rows = rows
            self._database.versions = versions
        self._clean_up()
        return []

    def _rollback(self) -> None:
        self._clean_up()

    def _assert_read_allowed(self) -> None:
        if self.has_written and not self._allow_reads_after_writes:
            raise ReadAfterWriteError('Firestore transactions must complete all reads before the first write')

    def _assert_reference_belongs(self, ref: StrictFirestoreDocument) -> None:
        if ref._database is not self._database:
            raise ForeignTransactionError('Firestore transaction and document reference must belong to the same store')

    def set(self, ref: StrictFirestoreDocument, data: dict[str, Any], merge: bool = False) -> None:
        self._assert_reference_belongs(ref)
        self.has_written = True
        payload = deepcopy(data)
        self.sets.append((ref.path, payload))
        if self._database._stage_transaction_writes:
            self._staged_operations.append(('set', ref.path, payload, merge))
            return
        if merge:
            self._database.rows.setdefault(ref.path, {}).update(payload)
        else:
            self._database.rows[ref.path] = payload
        self._database.versions[ref.path] = self._database.versions.get(ref.path, 0) + 1

    def create(self, ref: StrictFirestoreDocument, data: dict[str, Any]) -> None:
        self._assert_reference_belongs(ref)
        self.has_written = True
        staged_paths = {path for _operation, path, _payload, _merge in self._staged_operations}
        if ref.path in self._database.rows or ref.path in staged_paths:
            raise RuntimeError('document already exists')
        payload = deepcopy(data)
        self.creates.append((ref.path, payload))
        if self._database._stage_transaction_writes:
            self._staged_operations.append(('create', ref.path, payload, False))
            return
        self._database.rows[ref.path] = payload
        self._database.versions[ref.path] = self._database.versions.get(ref.path, 0) + 1

    def update(self, ref: StrictFirestoreDocument, patch: dict[str, Any]) -> None:
        self._assert_reference_belongs(ref)
        self.has_written = True
        if ref.path not in self._database.rows:
            raise RuntimeError('missing row')
        payload = deepcopy(patch)
        self.updates.append((ref.path, payload))
        if self._database._stage_transaction_writes:
            self._staged_operations.append(('update', ref.path, payload, True))
            return
        self._database.rows[ref.path].update(payload)
        self._database.versions[ref.path] = self._database.versions.get(ref.path, 0) + 1

    def delete(self, *args: Any, **kwargs: Any) -> None:
        raise UnsupportedFirestoreOperationError(f'StrictFirestore supports only {_SUPPORTED_OPERATIONS}')

    def get(self, *args: Any, **kwargs: Any) -> None:
        raise UnsupportedFirestoreOperationError(f'StrictFirestore supports only {_SUPPORTED_OPERATIONS}')

    def get_all(self, *args: Any, **kwargs: Any) -> None:
        raise UnsupportedFirestoreOperationError(f'StrictFirestore supports only {_SUPPORTED_OPERATIONS}')


class StrictFirestore:
    """In-memory Firestore double with strict read-before-write transactions.

    ``allow_reads_after_writes`` is an explicit, greppable opt-out for tests
    that intentionally do not exercise Firestore transaction semantics. It
    defaults to ``False`` and must not be used by production-boundary tests.
    """

    def __init__(
        self,
        rows: dict[tuple[str, ...], dict[str, Any]] | None = None,
        *,
        allow_reads_after_writes: bool = False,
        stage_transaction_writes: bool = False,
        fail_transaction_commit: bool = False,
    ):
        self.rows = deepcopy(rows or {})
        self.versions = {path: 0 for path in self.rows}
        self.lock = RLock()
        self._allow_reads_after_writes = allow_reads_after_writes
        self._stage_transaction_writes = stage_transaction_writes
        self._fail_transaction_commit = fail_transaction_commit
        self.transactions: list[StrictFirestoreTransaction] = []

    def collection(self, name: str) -> StrictFirestoreCollection:
        return StrictFirestoreCollection(self, (name,))

    def transaction(self) -> StrictFirestoreTransaction:
        transaction = StrictFirestoreTransaction(self, allow_reads_after_writes=self._allow_reads_after_writes)
        self.transactions.append(transaction)
        return transaction

    def write_option(self, *, last_update_time: int) -> StrictFirestoreWriteOption:
        return StrictFirestoreWriteOption(last_update_time)
