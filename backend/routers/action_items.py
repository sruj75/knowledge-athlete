import hashlib
import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Optional, List
from datetime import datetime, timezone

import database.action_items as action_items_db
from database.firestore_transaction_retry import FirestoreContentionExhausted
from database.vector_db import (
    upsert_action_item_vector,
    upsert_action_item_vectors_batch,
    delete_action_item_vector,
    delete_action_item_vectors_batch,
    search_action_items_by_vector,
)
from utils.other import endpoints as auth
from utils.notifications import (
    send_action_item_data_message,
    send_action_item_update_message,
    send_action_item_deletion_message,
    send_action_items_batch_deletion_message,
    sync_action_item_reminder,
)
from pydantic import BaseModel, Field, ValidationError
from models.shared import StatusResponse
from models.action_item import (
    ActionItemCreateRequest,
    ActionItemResponse,
    ActionItemUpdateRequest,
    ActionItemsResponse,
    ActionItemsSearchResponse,
)
from utils.task_intelligence import task_links

router = APIRouter()

logger = logging.getLogger(__name__)

# Import-compatible aliases; canonical ownership lives in models.action_item.
CreateActionItemRequest = ActionItemCreateRequest
UpdateActionItemRequest = ActionItemUpdateRequest


def _batch_mutation_response(result, *, locked_ids: Optional[set[str]] = None) -> dict:
    """Preserve legacy success shape unless there is partial-outcome detail.

    Mobile clients historically treat batch endpoints as boolean success paths,
    and the hermetic e2e harness pins that happy-path contract. Missing/no-op
    details are only emitted when they carry actionable information.
    """
    body = {"status": "ok", "updated_count": result.updated_count}
    locked_ids = locked_ids or set()
    if result.missing_ids or result.noop_ids or locked_ids:
        body.update(result.model())
        if locked_ids:
            body["locked_ids"] = sorted(locked_ids)
    return body


class ActionItemIdsResponse(BaseModel):
    ids: List[str]


class BatchMutationResponse(BaseModel):
    status: str
    updated_count: int
    updated_ids: Optional[List[str]] = None
    missing_ids: Optional[List[str]] = None
    noop_ids: Optional[List[str]] = None
    locked_ids: Optional[List[str]] = None


class BatchDeleteActionItemsResponse(BaseModel):
    status: str
    deleted_count: int
    deleted_ids: List[str]


class BatchCreateActionItemsResponse(BaseModel):
    action_items: List[ActionItemResponse]
    created_count: int


def _safe_action_item_responses(items, *, uid: str = '', context: str = '') -> List[ActionItemResponse]:
    """Build ActionItemResponse objects from raw records, skipping any that fail
    validation so one malformed or legacy item cannot 500 a whole list endpoint."""
    responses: List[ActionItemResponse] = []
    for item in items:
        try:
            responses.append(ActionItemResponse(**item))
        except ValidationError:
            item_id = item.get('id') if isinstance(item, dict) else None
            suffix = f', {context}' if context else ''
            logger.warning('Skipping malformed action item %s (uid=%s%s)', item_id, uid, suffix)
    return responses


def _get_valid_action_item(uid: str, action_item_id: str) -> dict:
    action_item = action_items_db.get_action_item(uid, action_item_id)
    if not action_item:
        raise HTTPException(status_code=404, detail="Action item not found")

    if action_item.get('is_locked', False):
        raise HTTPException(status_code=402, detail="A paid plan is required to access this action item.")

    return action_item


# *****************************
# ******* BATCH OPERATIONS ****
# *****************************


class BatchUpdateActionItemEntry(BaseModel):
    id: str
    sort_order: Optional[int] = None
    indent_level: Optional[int] = Field(default=None, ge=0, le=3)


class BatchUpdateActionItemsRequest(BaseModel):
    items: List[BatchUpdateActionItemEntry] = Field(..., max_length=500)


@router.patch(
    "/v1/action-items/batch",
    response_model=BatchMutationResponse,
    response_model_exclude_none=True,
    tags=['action-items'],
)
def batch_update_action_items(request: BatchUpdateActionItemsRequest, uid: str = Depends(auth.get_current_user_uid)):
    """Batch update sort_order and indent_level for multiple action items."""
    result = action_items_db.batch_update_action_items(uid, request.items)
    return _batch_mutation_response(result)


# *****************************
# ******** CRUD ROUTES ********
# *****************************


def _content_idempotency_key(uid: str, description: str) -> str:
    """Stable idempotency key from (uid, normalized description).

    Two POSTs from the same user with the same description (modulo case +
    surrounding whitespace) collapse to the same key, so a flaky-network
    retry no longer creates a duplicate Firestore document.

    Uses a length-prefixed encoding so the boundary between ``uid`` and
    ``description`` is unambiguous: ``f"{len(uid)}:{uid}:{description}"``.
    Without this, a uid containing ``:`` (federated identities, future
    multi-tenant ids) could collide with a different ``(uid, description)``
    pair after concatenation.
    """
    normalized = (description or '').strip().lower()
    payload = f"{len(uid)}:{uid}:{normalized}"
    return hashlib.sha256(payload.encode('utf-8')).hexdigest()


@router.post("/v1/action-items", response_model=ActionItemResponse, tags=['action-items'])
def create_action_item(request: ActionItemCreateRequest, uid: str = Depends(auth.get_current_user_uid)):
    """Create a new action item.

    Content-idempotent on (uid, normalized description): a retry of the same
    request returns the original action_item rather than creating a duplicate.
    """
    try:
        task_links.validate_task_links(uid, goal_id=request.goal_id, workstream_id=request.workstream_id)
    except task_links.TaskLinkValidationError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    action_item_data = request.storage_payload()

    idempotency_key = _content_idempotency_key(uid, request.description)
    try:
        action_item_id = action_items_db.create_action_item(uid, action_item_data, idempotency_key=idempotency_key)
    except FirestoreContentionExhausted as exc:
        raise HTTPException(status_code=503, detail="Service temporarily unavailable") from exc
    except action_items_db.TaskRelationshipConflictError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    action_item = action_items_db.get_action_item(uid, action_item_id)

    if not action_item:
        raise HTTPException(status_code=500, detail="Failed to create action item")

    # Schedule a reminder only for an open task with a due date — an already-completed item must
    # not arm a reminder (#5085).
    if request.due_at and not request.completed:
        send_action_item_data_message(
            user_id=uid,
            action_item_id=action_item_id,
            description=request.description,
            due_at=request.due_at.isoformat(),
        )

    upsert_action_item_vector(uid, action_item_id, request.description)

    return ActionItemResponse(**action_item)


def _ensure_aware(value: datetime) -> datetime:
    # FastAPI parses a query datetime as naive or timezone-aware depending on whether the client
    # included a UTC offset. Normalize to timezone-aware (UTC) so comparing the two ends of a date
    # range never raises TypeError on mixed awareness (which would surface as a 500).
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)


@router.get("/v1/action-items", response_model=ActionItemsResponse, tags=['action-items'])
def get_action_items(
    limit: int = Query(50, ge=1, le=500, description="Maximum number of action items to return"),
    offset: int = Query(0, ge=0, description="Number of action items to skip"),
    completed: Optional[bool] = Query(None, description="Filter by completion status"),
    conversation_id: Optional[str] = Query(None, description="Filter by conversation ID"),
    start_date: Optional[datetime] = Query(None, description="Filter by creation start date (inclusive)"),
    end_date: Optional[datetime] = Query(None, description="Filter by creation end date (inclusive)"),
    due_start_date: Optional[datetime] = Query(None, description="Filter by due start date (inclusive)"),
    due_end_date: Optional[datetime] = Query(None, description="Filter by due end date (inclusive)"),
    uid: str = Depends(auth.get_current_user_uid),
):
    """Get action items for the current user."""
    if start_date is not None and end_date is not None and _ensure_aware(start_date) > _ensure_aware(end_date):
        raise HTTPException(status_code=400, detail="start_date must be earlier than or equal to end_date")
    if (
        due_start_date is not None
        and due_end_date is not None
        and _ensure_aware(due_start_date) > _ensure_aware(due_end_date)
    ):
        raise HTTPException(status_code=400, detail="due_start_date must be earlier than or equal to due_end_date")

    action_items = action_items_db.get_action_items(
        uid=uid,
        conversation_id=conversation_id,
        completed=completed,
        start_date=start_date,
        end_date=end_date,
        due_start_date=due_start_date,
        due_end_date=due_end_date,
        limit=limit + 1,
        offset=offset,
    )

    has_more = len(action_items) > limit
    action_items = action_items[:limit]

    for item in action_items:
        if item.get('is_locked', False):
            description = item.get('description', '')
            item['description'] = (description[:70] + '...') if len(description) > 70 else description

    response_items = _safe_action_item_responses(action_items, uid=uid)

    return {"action_items": response_items, "has_more": has_more}


@router.get("/v1/action-items/search", response_model=ActionItemsSearchResponse, tags=['action-items'])
def search_action_items(
    query: str = Query(..., min_length=1, description="Search query"),
    limit: int = Query(10, ge=1, le=50, description="Maximum results"),
    uid: str = Depends(auth.get_current_user_uid),
):
    """Semantic search across action items using vector similarity."""
    action_item_ids = search_action_items_by_vector(uid, query, limit=limit)
    if not action_item_ids:
        return {"action_items": []}

    action_items = action_items_db.get_action_items_by_ids(uid, action_item_ids)
    action_items = [item for item in action_items if not item.get('is_locked', False)]
    return {"action_items": _safe_action_item_responses(action_items, uid=uid)}


@router.get("/v1/action-items/ids", response_model=ActionItemIdsResponse, tags=['action-items'])
def list_action_item_ids(uid: str = Depends(auth.get_current_user_uid)):
    """Return all of the user's action-item IDs (IDs only, no field reads).

    A lightweight way for a client to reconcile which tasks it has without paging the full
    list. Declared before /v1/action-items/{action_item_id} so the static path is not
    captured as an action item id.
    """
    return {"ids": action_items_db.get_action_item_ids(uid)}


@router.get("/v1/action-items/{action_item_id}", response_model=ActionItemResponse, tags=['action-items'])
def get_action_item(action_item_id: str, uid: str = Depends(auth.get_current_user_uid)):
    """Get a specific action item by ID."""
    action_item = _get_valid_action_item(uid, action_item_id)

    if not action_item:
        raise HTTPException(status_code=404, detail="Action item not found")

    return ActionItemResponse(**action_item)


@router.patch("/v1/action-items/{action_item_id}", response_model=ActionItemResponse, tags=['action-items'])
def update_action_item(
    action_item_id: str, request: ActionItemUpdateRequest, uid: str = Depends(auth.get_current_user_uid)
):
    """Update an action item."""
    # Check if action item exists
    existing_item = _get_valid_action_item(uid, action_item_id)
    if not existing_item:
        raise HTTPException(status_code=404, detail="Action item not found")

    proposed_goal_id = request.goal_id if 'goal_id' in request.model_fields_set else existing_item.get('goal_id')
    proposed_workstream_id = (
        request.workstream_id if 'workstream_id' in request.model_fields_set else existing_item.get('workstream_id')
    )
    try:
        task_links.validate_task_links(uid, goal_id=proposed_goal_id, workstream_id=proposed_workstream_id)
    except task_links.TaskLinkValidationError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    update_data = request.storage_payload()
    if request.completed is True or request.status == 'completed':
        update_data['completed_at'] = datetime.now(timezone.utc)
    elif 'completed' in update_data or 'status' in update_data:
        update_data['completed_at'] = None

    # Update the action item
    try:
        success = action_items_db.update_action_item(uid, action_item_id, update_data)
    except FirestoreContentionExhausted as exc:
        raise HTTPException(status_code=503, detail="Service temporarily unavailable") from exc
    except action_items_db.TaskRelationshipConflictError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    if not success:
        raise HTTPException(status_code=500, detail="Failed to update action item")

    if request.description is not None:
        upsert_action_item_vector(uid, action_item_id, request.description)

    # Return updated action item
    updated_item = action_items_db.get_action_item(uid, action_item_id)
    if updated_item is None:
        raise HTTPException(status_code=500, detail="Updated action item could not be loaded")

    if 'completed' in update_data or 'due_at' in update_data:
        sync_action_item_reminder(
            user_id=uid,
            action_item_id=action_item_id,
            description=updated_item.get('description', ''),
            completed=bool(updated_item.get('completed')),
            due_at=updated_item.get('due_at'),
        )

    return ActionItemResponse(**updated_item)


@router.patch("/v1/action-items/{action_item_id}/completed", response_model=ActionItemResponse, tags=['action-items'])
def toggle_action_item_completion(
    action_item_id: str,
    completed: bool = Query(description="Whether to mark as completed or not"),
    uid: str = Depends(auth.get_current_user_uid),
):
    """Mark an action item as completed or uncompleted."""
    # Check if action item exists
    existing_item = _get_valid_action_item(uid, action_item_id)
    if not existing_item:
        raise HTTPException(status_code=404, detail="Action item not found")

    # Update completion status
    success = action_items_db.mark_action_item_completed(uid, action_item_id, completed)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to update action item")

    # Return updated action item
    updated_item = action_items_db.get_action_item(uid, action_item_id)
    if updated_item is None:
        raise HTTPException(status_code=500, detail="Updated action item could not be loaded")

    sync_action_item_reminder(
        user_id=uid,
        action_item_id=action_item_id,
        description=updated_item.get('description', ''),
        completed=completed,
        due_at=updated_item.get('due_at'),
    )

    return ActionItemResponse(**updated_item)


@router.delete("/v1/action-items/{action_item_id}", status_code=204, tags=['action-items'])
def delete_action_item(action_item_id: str, uid: str = Depends(auth.get_current_user_uid)):
    """Delete an action item."""
    _get_valid_action_item(uid, action_item_id)
    success = action_items_db.delete_action_item(uid, action_item_id)
    if not success:
        raise HTTPException(status_code=404, detail="Action item not found")

    delete_action_item_vector(uid, action_item_id)

    # Send FCM deletion message to cancel scheduled notification
    send_action_item_deletion_message(user_id=uid, action_item_id=action_item_id)


class BatchDeleteActionItemsRequest(BaseModel):
    ids: List[str] = Field(description="IDs of action items to delete", min_length=1, max_length=10000)


@router.post("/v1/action-items/batch-delete", response_model=BatchDeleteActionItemsResponse, tags=['action-items'])
def batch_delete_action_items(request: BatchDeleteActionItemsRequest, uid: str = Depends(auth.get_current_user_uid)):
    """Delete multiple action items in one request.

    Firestore deletes go through chunked batched commits in the DB layer; the
    vector store delete and the FCM cancellation message both use their batch
    helpers — no per-id loop on this hot path.
    """
    deleted_ids = action_items_db.delete_action_items_batch(uid, request.ids)

    if deleted_ids:
        delete_action_item_vectors_batch(uid, deleted_ids)
        send_action_items_batch_deletion_message(user_id=uid, action_item_ids=deleted_ids)

    return {"status": "Ok", "deleted_count": len(deleted_ids), "deleted_ids": deleted_ids}


@router.post("/v1/action-items/batch", response_model=BatchCreateActionItemsResponse, tags=['action-items'])
def create_action_items_batch(
    action_items: List[ActionItemCreateRequest], uid: str = Depends(auth.get_current_user_uid)
):
    """Create multiple action items in a batch."""
    if not action_items:
        return {"action_items": [], "created_count": 0}

    # Prepare action items data
    action_items_data = []
    for item in action_items:
        try:
            task_links.validate_task_links(uid, goal_id=item.goal_id, workstream_id=item.workstream_id)
        except task_links.TaskLinkValidationError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        action_items_data.append(item.storage_payload())

    # Create batch
    try:
        created_ids = action_items_db.create_action_items_batch(uid, action_items_data)
    except FirestoreContentionExhausted as exc:
        raise HTTPException(status_code=503, detail="Service temporarily unavailable") from exc
    except action_items_db.TaskRelationshipConflictError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    # Fetch created items and send FCM messages
    created_items = []
    for idx, item_id in enumerate(created_ids):
        item = action_items_db.get_action_item(uid, item_id)
        if item:
            created_items.append(ActionItemResponse(**item))

            # Send FCM data message if action item has a due date
            due_at = action_items[idx].due_at if idx < len(action_items) else None
            if due_at is not None:
                send_action_item_data_message(
                    user_id=uid,
                    action_item_id=item_id,
                    description=action_items[idx].description,
                    due_at=due_at.isoformat(),
                )

    upsert_action_item_vectors_batch(
        uid,
        [
            {'action_item_id': aid, 'description': data['description']}
            for aid, data in zip(created_ids, action_items_data)
        ],
    )

    return {"action_items": created_items, "created_count": len(created_items)}
