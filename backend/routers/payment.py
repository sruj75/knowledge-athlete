from __future__ import annotations

import logging
from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from database import users as users_db
from utils.billing.config import BillingConfigurationError, load_billing_config
from utils.billing.service import (
    BillingDisabledError,
    BillingOfferError,
    BillingService,
    BillingWebhookVerificationError,
)
from utils.executors import db_executor, run_blocking
from utils.log_sanitizer import sanitize
from utils.other import endpoints as auth

logger = logging.getLogger(__name__)
router = APIRouter()


class CreateCheckoutRequest(BaseModel):
    offer_id: str


class PaymentCheckoutSessionResponse(BaseModel):
    url: str
    session_id: str


class CustomerPortalSessionResponse(BaseModel):
    url: str


class BillingWebhookResponse(BaseModel):
    status: str


async def get_billing_service() -> AsyncIterator[BillingService]:
    try:
        service = BillingService(load_billing_config())
    except BillingConfigurationError as exc:
        raise HTTPException(
            status_code=503,
            detail={'code': 'billing_misconfigured', 'message': 'Billing is temporarily unavailable.'},
        ) from exc
    try:
        yield service
    finally:
        await service.close()


def _billing_http_error(exc: Exception) -> HTTPException:
    if isinstance(exc, BillingDisabledError):
        return HTTPException(
            status_code=503,
            detail={'code': exc.code, 'message': 'Billing is not available in this build.'},
        )
    if isinstance(exc, BillingOfferError):
        return HTTPException(
            status_code=400,
            detail={'code': exc.code, 'message': 'That billing offer is unavailable.'},
        )
    if isinstance(exc, BillingWebhookVerificationError):
        return HTTPException(
            status_code=401,
            detail={'code': exc.code, 'message': 'Webhook authentication failed.'},
        )
    if isinstance(exc, ValueError):
        return HTTPException(
            status_code=400,
            detail={'code': 'billing_profile_unavailable', 'message': str(exc)},
        )
    logger.error('Billing provider operation failed: %s', sanitize(str(exc)))
    return HTTPException(
        status_code=502,
        detail={'code': 'billing_provider_error', 'message': 'The billing provider request failed.'},
    )


@router.post(
    '/v1/payments/checkout-session',
    response_model=PaymentCheckoutSessionResponse,
)
async def create_checkout_session_endpoint(
    request: CreateCheckoutRequest,
    uid: str = Depends(auth.get_current_user_uid),
    billing: BillingService = Depends(get_billing_service),
):
    try:
        session = await billing.create_checkout(uid, request.offer_id)
    except Exception as exc:
        raise _billing_http_error(exc) from exc
    return PaymentCheckoutSessionResponse(url=session.url, session_id=session.session_id)


@router.post('/v1/payments/customer-portal', response_model=CustomerPortalSessionResponse)
async def create_customer_portal_endpoint(
    uid: str = Depends(auth.get_current_user_uid),
    billing: BillingService = Depends(get_billing_service),
):
    try:
        billing.ensure_active()
        subscription = await run_blocking(db_executor, users_db.get_existing_user_subscription, uid)
        customer_id = getattr(subscription, 'billing_customer_id', None) if subscription else None
        url = await billing.create_portal(customer_id or '')
    except Exception as exc:
        raise _billing_http_error(exc) from exc
    return CustomerPortalSessionResponse(url=url)


@router.post('/v1/dodo/webhook', response_model=BillingWebhookResponse)
async def dodo_webhook_endpoint(
    request: Request,
    billing: BillingService = Depends(get_billing_service),
):
    try:
        raw_body = (await request.body()).decode('utf-8')
        outcome = await billing.process_webhook(raw_body, request.headers)
    except Exception as exc:
        raise _billing_http_error(exc) from exc
    return BillingWebhookResponse(status=outcome)


@router.get('/v1/payments/success', response_class=HTMLResponse)
def payment_success():
    return HTMLResponse(
        content='''
        <html>
            <head><title>Success</title></head>
            <body style="font-family: sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; flex-direction: column;">
                <h1>Payment Successful!</h1>
                <p>Your subscription is being confirmed. You can close this window and return to the app.</p>
            </body>
        </html>
        '''
    )


@router.get('/v1/payments/cancel', response_class=HTMLResponse)
def payment_cancel():
    return HTMLResponse(
        content='''
        <html>
            <head><title>Cancelled</title></head>
            <body style="font-family: sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; flex-direction: column;">
                <h1>Payment Cancelled</h1>
                <p>No billing change was made. You can return to the app.</p>
            </body>
        </html>
        '''
    )


@router.get('/v1/payments/portal-return', response_class=HTMLResponse)
def portal_return():
    return HTMLResponse(
        content='''
        <html>
            <head><title>Portal Complete</title></head>
            <body style="font-family: sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; flex-direction: column;">
                <h1>Settings Updated</h1>
                <p>Your billing settings have been updated. You can close this window and return to the app.</p>
            </body>
        </html>
        '''
    )
