import os
from typing import Any, Dict, Optional, cast

from fastapi import APIRouter, Depends, Header, HTTPException

import database.notifications as notification_db
from models.other import FcmTokenResponse, SaveFcmTokenRequest
from utils.notifications import (
    send_notification,
)
from utils.other import endpoints as auth

# logger = logging.getLogger('uvicorn.error')
# logger.setLevel(logging.DEBUG)
router = APIRouter()


@router.post('/v1/users/fcm-token', response_model=FcmTokenResponse)
def save_token(
    data: SaveFcmTokenRequest,
    uid: str = Depends(auth.get_current_user_uid),
    x_app_platform: Optional[str] = Header(None, alias='X-App-Platform'),
    x_device_id_hash: Optional[str] = Header(None, alias='X-Device-Id-Hash'),
) -> FcmTokenResponse:
    platform = x_app_platform or 'unknown'
    device_hash = x_device_id_hash or 'default'

    # Create key: ios_abc123, android_xyz456, macos_def789
    device_key = f"{platform}_{device_hash}"

    token_data: Dict[str, Any] = data.model_dump()
    token_data['device_key'] = device_key

    notification_db.save_token(uid, token_data)
    return FcmTokenResponse(status='Ok')


# ******************************************************
# ******************* TEAM ENDPOINTS *******************
# ******************************************************


@router.post('/v1/notification')
def send_notification_to_user(data: Dict[str, Any], secret_key: str = Header(...)) -> Dict[str, str]:
    if secret_key != os.getenv('ADMIN_KEY'):
        raise HTTPException(status_code=403, detail='You are not authorized to perform this action')
    if not data.get('uid'):
        raise HTTPException(status_code=400, detail='uid is required')
    uid = cast(str, data['uid'])
    title = cast(str, data['title'])
    body = cast(str, data['body'])
    notification_data = cast(Dict[str, Any], data.get('data', {}))
    send_notification(uid, title, body, notification_data)
    return {'status': 'Ok'}
