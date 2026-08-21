# LIFECYCLE: permanent

# Dodo integration handoff

## Current product state

The MVP remains free through all six implementation waves. `BILLING_MODE=disabled` is the required runtime state during that period. It returns no purchasable catalog, exposes no checkout or portal action, constructs no Dodo client, and makes no Dodo or Stripe request. The visible usage-limit action is **Skip**; it dismisses the presentation, grants no entitlement, and does not clear trial, quota, or fair-use state.

This disabled checkpoint is sufficient for Wave 3 repository dependencies. It is not final S-18 acceptance and it does not authorize test or live payment activity.

## Behavior retained for later activation

The repository keeps the provider-neutral behavior needed for a paid release:

- server-owned bounded and unlimited offers and monthly/annual presentation;
- hosted checkout in the retained Mac web sheet;
- signed, idempotent, out-of-order-safe webhook projection;
- bounded post-checkout reconciliation;
- hosted customer portal for plan changes, payment methods, invoices, and cancellation;
- cancellation-at-period-end and access-end presentation;
- backend-authoritative subscription, quota, managed-access, and fair-use mapping;
- retry/failure recovery and account-deletion cancellation safety.

Activation must preserve these behaviors. It must not add a new onboarding paywall or make a redirect URL authoritative for entitlement.

## Required external resources

Create test resources only after Wave 6 and explicit authorization:

- a Dodo test-mode account and API key supplied through `DODO_PAYMENTS_API_KEY`;
- a test-mode HTTPS webhook targeting `/v1/dodo/webhook` and its signing key supplied through `DODO_PAYMENTS_WEBHOOK_KEY`;
- test-mode subscription products for every approved bounded/unlimited interval;
- one normalized server-owned offer catalog supplied through `DODO_BILLING_CATALOG_JSON`;
- a reachable test backend, Firebase test principal, and disposable test customer;
- access to backend logs, fallback metrics, webhook receipts, subscription projection, quota, fair-use, and account-deletion evidence.

Test and live resources are separate. Dodo documents separate API hosts, products, keys, and webhooks for [test and live modes](https://docs.dodopayments.com/miscellaneous/test-mode-vs-live-mode). Never copy secret values into source, Markdown, logs, screenshots, test fixtures, commit messages, or PR bodies. Never commit real product IDs, customer/subscription IDs, or Stripe/Omi payment identifiers. Repository fixtures must remain obviously synthetic.

## Post-Wave-6 test-mode acceptance

Use `BILLING_MODE=dodo_test` only in a bounded test environment, then collect evidence for this sequence:

1. Validate startup fails closed when the API key, webhook key, or catalog is missing or malformed.
2. Read `/v1/users/me/subscription` and confirm only the normalized server-owned test offers are presented.
3. Start `/v1/payments/checkout-session` from a selected opaque offer. Confirm the backend resolves the test product and the Mac opens the returned hosted checkout URL.
4. Complete one successful test checkout using Dodo's [test-mode payment process](https://docs.dodopayments.com/miscellaneous/testing-process). Confirm the redirect is presentation only.
5. Receive and verify the exact raw webhook body and Standard Webhooks headers. Confirm duplicate delivery is a no-op, an older event cannot overwrite newer state, and an invalid signature grants nothing. See Dodo's [webhook security guidance](https://docs.dodopayments.com/developer-resources/webhooks).
6. Confirm bounded reconciliation stops after its existing read budget, recognizes only the expected normalized offer, and refreshes subscription, quota, paywall, and fair-use state.
7. Open `/v1/payments/customer-portal`; verify invoices/payment methods and each supported plan change through Dodo's hosted [Customer Portal](https://docs.dodopayments.com/features/customer-portal).
8. Cancel at the next billing date. Confirm **Access ends** is accurate, access remains until that instant, and the terminal webhook removes paid access afterward.
9. Exercise quota denial, fair-use thresholds, renewal/payment failure, delayed/duplicate/out-of-order webhooks, provider timeouts, restart, and reconciliation recovery without creating a second entitlement owner.
10. Exercise account deletion for an active or possibly billable subscription. Irreversible identity deletion must wait until provider cancellation is confirmed and the durable deletion workflow completes.
11. Confirm the Mac's retained plan/usage screens, checkout Close/success/cancel handling, Refresh, portal return, and error states match the free-MVP behavior outside the newly active provider calls.
12. Record commands, timestamps, test resource names, redacted request/event IDs, screenshots, logs, metric queries, final subscription/quota state, and cleanup results. Remove the disposable customer and disable the test webhook when the run ends.

## Separately authorized live activation

Live activation is a distinct release operation after test-mode acceptance. It requires explicit user authorization, verified business status, separately created live products/API key/webhook/signing key/catalog, a reviewed deployment diff, monitoring ownership, and a rollback window.

The first live proof is deliberately bounded: activate `BILLING_MODE=dodo_live` for the approved environment, perform one low-value transaction with an authorized test customer, verify the signed webhook and normalized entitlement/quota projection, open the portal, cancel, verify access-end behavior, and retain the provider receipt. Do not expand traffic or offers during this proof.

Rollback means restoring `BILLING_MODE=disabled`, removing purchasable catalog exposure, confirming checkout/portal routes return the typed disabled response without provider construction, retaining already-received webhook receipts for idempotency, and reconciling the bounded live test subscription before deleting any provider resource. A rollback never fabricates free or paid entitlement state.

## Final evidence checklist

- [ ] All six waves are complete and the 714/714 requirements ledger passes.
- [ ] Dodo test credentials, webhook, products, and catalog were created outside the repository.
- [ ] Checkout, signed webhook, duplicate/stale ordering, and reconciliation passed in test mode.
- [ ] Portal, plan change, cancellation/access-end, quota/fair-use, and failure recovery passed.
- [ ] Active-subscription account deletion passed without orphaned billing.
- [ ] No credential, real product/customer/subscription ID, or Stripe/Omi payment identifier appears in git history or artifacts.
- [ ] Test resources and disposable customer data were cleaned up.
- [ ] Live activation received separate explicit authorization.
- [ ] One bounded live transaction and cancellation passed with monitoring and rollback evidence.
- [ ] S-18 was marked complete only after every preceding item passed.
