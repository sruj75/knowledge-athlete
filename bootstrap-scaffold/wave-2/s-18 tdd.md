# S-18 TDD plan — replace Stripe with Dodo while preserving billing behavior

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | **S-18** |
| Wave | **2 — make retained Mac behavior authoritative** |
| Name | **Replace Stripe with Dodo while preserving billing behavior** |
| Type | Provider adaptation and plan simplification |
| Primary decisions | **IR-006, IR-007, IR-191 through IR-203, IR-700, IR-831, IR-835** |
| Roadmap source | [`../deletion-map.md`](../deletion-map.md), **S-18 — Replace Stripe with Dodo while preserving billing behavior** |
| Decision authority | [`../requirements-challenge.md`](../requirements-challenge.md) |
| Research lead | [`../deletion-slice-research.md`](../deletion-slice-research.md), **Payments, plans, trials, quota, and usage** |
| Delivery boundary | One S-18 repository change, ten ordered TDD cycles, one interim MVP-disabled checkpoint, and separately authorized future Dodo activation leading to final S-18 closure |

This file is an implementation plan, not implementation evidence. Creating it changes no product code, test, generated contract, configuration, workflow, live provider account, or cloud resource.

## 2. Planning status and pinned baseline

**Planning status:** ready for the configuration-independent fences, disabled-MVP path, provider adapter, hermetic provider tests, and repository cleanup after the execution-time entry gates below. The MVP must ship with transactions impossible and without Dodo credentials. Full provider activation remains deliberately blocked until the commercial catalog, Dodo test credentials, webhook key, and later production credentials are supplied and separately authorized.

The inspected baseline is:

```text
HEAD 0d9934c9d2ed61bd02ac8784e50f56ee816257c3
```

The required ancestry gate passed during planning:

```bash
git merge-base --is-ancestor 0d9934c HEAD
```

The requirements ledger also passed during planning:

```text
Requirements ledger validation: PASS (714 indexed rows, 714 detailed sections, all reviewed)
```

At this snapshot, the Wave 2 plans are untracked planning artifacts, not integrated implementation. No product test or user path was run while writing this document. Commands below are future execution requirements unless explicitly identified as a planning-time read-only check.

### MVP direction added after the roadmap brief

The execution target has two phases:

1. **MVP-disabled phase:** no Dodo credentials or product identifiers are configured; no transaction, checkout URL, portal URL, customer, subscription, or paid entitlement can be created. The visible usage/paywall primary action is literally **Skip**. On the current post-onboarding usage-limit surface it only dismisses the presentation and returns to the underlying screen. It never clears quota/trial state and never writes paid state.
2. **Future Dodo-active phase:** the already-built architecture is activated first in Dodo test mode and only later in live mode. Rich catalog selection, hosted checkout, bounded reconciliation, webhook projection, hosted portal, cancellation, quota, and fair-use mapping then operate without another architecture rewrite.

There is no billing/paywall step in the current `SBOnboardingModel.Step` graph, and S-17 authorizes an exact onboarding sequence that does not contain one. S-18 must therefore not invent a new onboarding screen. If the product requires a literal paywall between two onboarding steps, execution stops until the requirements ledger and S-17 owner identify its exact position and advance callback. Once authorized, disabled mode must use S-17's existing advance policy; it must still perform no billing mutation. This is the only unresolved UI placement question. It does not block adapting the current `UsageLimitPopupView` to the safe Skip behavior.

## 3. Outcome

Replace the Stripe implementation and all Stripe-only residue with one Dodo-ready billing module while keeping the backend authoritative for subscription projection, trials, quota, usage, managed subscriber access, and fair-use classification.

The end state has one explicit runtime mode:

```text
BILLING_MODE=disabled   (default MVP; no credentials accepted or required; no transactions)
BILLING_MODE=dodo_test  (future activation; complete test credentials/catalog required)
BILLING_MODE=dodo_live  (future activation; complete production credentials/catalog required)
```

`disabled` is a real product state, not a successful checkout simulation. The authenticated subscription response says purchasing is unavailable, the Mac renders Skip instead of a purchase action, and every transaction-capable route fails closed with one typed `billing_disabled` response without constructing a Dodo client or making a network request. The existing free/trial subscription and quota projection remains authoritative; Skip grants nothing.

In either active mode, the retained flow is:

```text
Mac Account & Plan rich offer card
  -> authenticated backend checkout request using a server-issued offer identity
  -> backend maps offer to the configured Dodo product
  -> Dodo hosted checkout in the retained WKWebView sheet
  -> exact success/cancel interception
  -> signed, idempotent Dodo subscription webhook
  -> Firestore subscription projection + cache invalidation
  -> eight reads at one-second intervals for the expected offer/product
  -> usage/quota/paywall refresh

paid subscriber Manage
  -> authenticated backend portal request
  -> Dodo hosted customer portal in the default browser
  -> plan change, payment method, invoices, or cancellation
  -> webhook updates cancel-at-next-billing-date/access-end projection
```

The end state has no Stripe SDK, identifiers, environment variables, webhook route, price lookup, schedule, promo, reactivation path, local checkout simulator, Omi legacy plan migration, paid overage, BYOK/free-plan bypass, duplicate catalog reconstruction, or unused detailed-usage API.

## 4. Authorizing requirements

The live requirements challenge remains the decision authority. The MVP-disabled staging above does not change the retained future behavior; it changes when external billing is activated. If the ledger is changed to require immediate transactions or to insert a new onboarding step, stop and re-plan rather than silently choosing a competing interpretation.

| Decision | Required S-18 outcome | Protecting cycle(s) |
|---|---|---|
| IR-006 | Keep the Firebase account/entitlement boundary, trial, plans, quota, paywall, checkout, customer management, webhook, and account-deletion billing safety; replace Stripe with Dodo without redesigning the whole account architecture. | 1-6, 10 |
| IR-007 | Preserve normal paying-subscriber PTT through Firebase-authenticated backend entitlement and product-owned short-lived provider credentials; never reintroduce personal keys as a billing bypass. | 1, 7, 8, 10 |
| IR-191 | Keep the three-day trial exactly, keep `TRIAL_PAYWALL_ENABLED=false` by default, and retain trial endpoint, polling, countdown/cards, nudges, gates, debug modes, and tests. Skip may dismiss presentation but may not clear the trial/quota gate. | 1, 6, 10 |
| IR-192 | Keep the current plan card, loading/error states, status, price/interval, renewal/access-end display, Manage, and Refresh; derive them from the server's normalized Dodo projection. | 2, 5, 6 |
| IR-193 | Delete the Omi Plan Retiring card and `deprecated`/`deprecation_message` Python and Swift fields and tests. | 6 |
| IR-194 | Keep rich server-owned catalog cards, comparison, selection, and monthly/annual presentation for future Free-to-paid checkout after the exact commercial Dodo offer is supplied. In disabled MVP mode do not expose an actionable purchase control. | 1, 2, 4, 6 |
| IR-195 | Delete promotion field/state, checkout request property, backend validation/application, and tests; a future discount is provider-hosted only. | 6 |
| IR-196 | Keep the embedded WKWebView checkout sheet, Close, same-view new-window handling, and exact success/cancel interception for active Dodo mode; never collect card data locally. | 4 |
| IR-197 | Keep the bounded reconciliation at eight reads one second apart, match the expected normalized Dodo offer/product, refresh quota/paywall on success, and keep bounded timeout/error behavior. | 4 |
| IR-198 | Delete `completeLocalTestSubscriptionIfNeeded`, the extra GET-success completion, the missing Rust `/test/complete-subscription` call, and helper-only `isLocalURL`; retain real success/cancel routes and prove Dodo with signed hermetic fixtures, then sandbox webhooks. | 4, 10 |
| IR-199 | Delete Mac upgrade request/types/tests, `/v1/payments/upgrade-subscription`, Stripe schedules/proration/downgrade handling, and cloud-product unlock side effects. Free-to-paid uses checkout; paid changes, invoices, payment methods, and cancellation use Dodo's hosted portal. | 5, 6 |
| IR-200 | Delete `_try_reactivate_subscription`, its special response shape, Mac handling, and tests. Keep cancellation projection and display **Access ends**; reactivation/customer management belongs to the Dodo portal. | 5, 6 |
| IR-201 | Keep rich `available_plans` only inside `/v1/users/me/subscription`; delete the second `/v1/payments/available-plans`, Mac fallback catalog/title normalization/merger, second request, and exclusive tests. | 2, 6, 9 |
| IR-202 | Keep Account usage card/loading/progress/reset/warnings, shared Chat/PTT `FloatingBarUsageLimiter`, optimistic question increments, server snapshots for cost units, and fail-open local behavior; backend remains authoritative. | 1, 7, 10 |
| IR-203 | Delete overage UI, endpoint, models, `utils/overage`, paid quota bypass, and tests. All plans stop at their included allowance. Exact allowances remain a commercial-config gate. | 7 |
| IR-700 | Map the exact 2/8/10-hour bounded and 4/16/20-hour unlimited speech review thresholds from one explicit normalized entitlement property backed by the Dodo product mapping; keep the separate 30-hour ceiling. | 8 |
| IR-831 | Delete detailed LLM-usage reads, top-features, and personal self-report plus generated bindings, route policy, and tests; preserve server-recorded managed Chat/PTT counts and cost, idempotency, `/usage-quota`, total managed cost, billing, and LangSmith. | 7, 9 |
| IR-835 | Delete GET `/v1/users/me/usage`, its exclusive models/generated route/tests/docs; preserve the underlying usage recording, monthly subscription usage, quota, total managed cost, fair use, support needs, and Account usage card. | 7, 9 |

## 5. Dependencies and entry gates

### G0 — execution-time rebase and inventory refresh

Before the first RED:

1. Run the repository setup required before a first commit, fetch the target branch, keep the current branch name, and integrate current target work without losing `0d9934c` as an ancestor.
2. Record `git rev-parse HEAD origin/main`, rerun `git merge-base --is-ancestor 0d9934c HEAD`, and rerun the requirements validator.
3. Re-read the S-18 ledger sections and rerun the inventories in §§6-7 and residue searches in §13. Classify new callers rather than guessing them away.
4. Run the existing focused billing, trial, quota, fair-use, account-deletion, API-routing, generated-contract, and UI tests to distinguish pre-existing failures from intended REDs.
5. Stop if an assigned requirement changed, a released external caller is proven for a route planned for deletion, or the predecessor-owned account/session seams are not present. Do not bridge a missing predecessor with an alias or temporary compatibility route.

### G1 — S-07 managed-provider predecessor

S-18 consumes S-07's product-managed OpenAI/Gemini credential flow and the absence of customer BYOK. At the planning baseline, customer-key UI/callers still appear in `UsageLimitPopupView`, so implementation must rebase onto the integrated S-07 result and refresh the inventory. S-18 owns only the billing entitlement input to managed access. It must not recreate personal-key UI, a free-plan BYOK bypass, or provider-selection work owned by S-07.

Stop if S-07 is not integrated. There is no authorized temporary billing-to-BYOK path.

### G2 — S-08 account/session and deletion predecessor

S-18 consumes S-08's canonical Firebase identity/session and durable account-deletion handoff. It replaces only the provider-specific cancellation inside the claimed deletion worker. It must preserve deletion intent, retry/failure markers, auth deletion ordering, owner isolation, and the rule that an account with a possibly billable subscription is not irreversibly deleted until cancellation is confirmed.

Stop if S-08's final worker shape differs from the current `services/users/account_deletion.py` inventory; rebase and adapt at its documented seam rather than copying its work.

### G3 — Dodo contract and commercial catalog

The provider mechanics are grounded in current official Dodo documentation:

- The official [Python SDK](https://docs.dodopayments.com/developer-resources/sdks/python) supplies sync/async clients, `test_mode`/`live_mode`, checkout sessions, and environment-backed credentials.
- [Checkout Sessions](https://docs.dodopayments.com/api-reference/checkout-sessions/create) return a hosted checkout URL for a product cart; new subscriptions are created through checkout rather than the deprecated direct-subscription API.
- [Webhooks](https://docs.dodopayments.com/developer-resources/webhooks) use Standard Webhooks headers, HMAC verification over the raw body, unique webhook IDs, retries, and out-of-order delivery.
- [Subscription events](https://docs.dodopayments.com/developer-resources/webhooks/intents/subscription) include active, updated, on-hold, renewed, plan-changed, cancelled, failed, and expired states plus `cancel_at_next_billing_date`.
- A [Customer Portal session](https://docs.dodopayments.com/api-reference/customers/create-customer-portal-session) returns a hosted link, and the [portal](https://docs.dodopayments.com/features/customer-portal) owns plan changes, invoices, payment methods, and cancellation.
- [Product Collections](https://docs.dodopayments.com/features/product-collections) are the provider-side prerequisite for portal plan changes, and the [products API](https://docs.dodopayments.com/api-reference/products/get-products) is the provider catalog source.

Missing external inputs are:

- final internal plan/offer names, monthly and annual prices, included allowances, and card copy;
- the explicit mapping from each offer to a Dodo product and bounded/unlimited entitlement class;
- Dodo test API key, test webhook key, test business/product/customer setup, and test webhook endpoint;
- later Dodo production API key, webhook key, production products/collection, portal settings, and endpoint;
- separate authorization to install secrets, deploy, create or alter provider resources, run a test transaction, or activate live transactions.

Safe work before these inputs: cycles 1-10 can define and behavior-test the disabled mode, normalized models, adapter boundaries, signed local webhook fixtures, fail-closed active-mode validation, UI policy, deletion ordering, and all configuration-independent cleanup. Synthetic IDs in hermetic tests are fixtures only and may never become environment defaults.

Blocked without these inputs: real catalog values, a Dodo network call, dashboard webhook replay, test checkout, portal session, provider-side plan change/cancellation, production activation, and full operational closure.

### G4 — literal onboarding placement

The current retained S-17 sequence has no paywall. The immediately executable S-18 behavior is therefore:

```text
UsageLimitPopupView in disabled mode
  -> button title: Skip
  -> dismiss popup
  -> do not navigate to Account & Plan
  -> do not call checkout/portal
  -> do not clear trial, usage, paywall, or quota state
  -> next cost-bearing attempt remains gated by the backend/current local snapshot
```

If a new onboarding paywall is required, the missing input is its exact position in S-17's fixed sequence and the owner-approved advance transition. That one UI integration is blocked; all other S-18 work can proceed. S-18 supplies the billing-availability policy, while S-17 owns the onboarding step graph, persistence, Back/Skip semantics, and completion behavior.

## 6. Current production codeflow

### Catalog and subscription read

```text
Settings Account & Plan onAppear / Refresh
  -> SettingsContentView.loadSubscriptionInfo()
     -> GET /v1/users/me/subscription
        -> reconcile_basic_plan_with_stripe()
        -> Stripe subscription retrieve for current price
        -> get_user_valid_subscription() from users/{uid}.subscription
        -> local plan definitions + cached Stripe prices
        -> monthly usage + quota + rich available_plans
     -> second GET /v1/payments/available-plans
        -> a second Stripe-backed catalog
     -> Mac fallbackPlanCatalog + SubscriptionPlanCatalogMerger/title normalization
```

The target keeps only the first authenticated response. It carries the normalized subscription, usage/quota, billing availability, and rich offers when active. Disabled mode carries no actionable paid offer.

### Checkout, local simulator, and reconciliation

```text
plan card Select
  -> startCheckout(priceId)
     -> paid user: POST /v1/payments/upgrade-subscription
        -> Stripe schedule/proration path
     -> free user: POST /v1/payments/checkout-session
        -> promo validation
        -> Stripe reactivation shortcut or Checkout Session
        -> Stripe-hosted URL
     -> BillingWebFlow WKWebView
        -> /v1/payments/success or /cancel interception
        -> completeLocalTestSubscriptionIfNeeded()
        -> eight one-second GET /v1/users/me/subscription reads
        -> expected Stripe price + active paid plan
```

The target removes promo, reactivation, custom upgrade, local completion, and Stripe price identity. Disabled mode stops before the first backend transaction call. Active mode maps a server-issued offer to one configured Dodo product, hosts Dodo checkout in the existing sheet, and matches the resulting normalized offer/product projection.

### Webhook and subscription projection

```text
POST /v1/stripe/webhook
  -> Stripe signature parse
  -> checkout.session.completed / customer.subscription.* / schedule.*
  -> metadata uid or stripe_customer_id reverse lookup
  -> Subscription(stripe_subscription_id, current_price_id, periods, cancel flag)
  -> users/{uid}.subscription + stripe_customer_id
  -> Redis cache clear + fair-use state clear
  -> rejected cloud-product unlocks / paid notification side effects
```

The target uses one signed Dodo subscription webhook, a durable webhook-ID idempotency record, one UID/customer association, a monotonic provider-state projection, and only retained cache/fair-use invalidations. Duplicate and out-of-order delivery must not double-apply or allow an old cancellation to clobber a newer active offer. Deleted users must never be recreated.

### Portal, cancellation, and account deletion

```text
Manage
  -> POST /v1/payments/customer-portal
  -> stored Stripe customer or Stripe subscription lookup
  -> browser-hosted Stripe portal

DELETE /v1/payments/subscription
  -> direct Stripe cancellation (no current Mac caller)

claimed account-deletion worker
  -> users/{uid}.subscription.stripe_subscription_id
  -> Stripe cancel and confirmation
  -> billing failure marker on uncertainty
  -> only then auth/data deletion
```

The target uses the hosted Dodo portal for ordinary customer changes/cancellation and Dodo subscription cancellation only at the account-deletion safety boundary. In disabled mode a principal without a Dodo subscription proceeds; a principal with a possibly active Dodo subscription but no usable provider configuration fails closed and preserves the billing-failure retry state.

### Trial, paywall, quota, and managed access

```text
/v1/users/me/trial + AppState.fetchTrialMetadata()
  -> sticky isPaywalled state
  -> menu/capture admission + TrialBannerService + trial cards

chat.py / desktop_chat.py
  -> enforce_chat_quota()
  -> current paid-plan bypass / overage path

listen bootstrap/runtime + fair_use.py
  -> get_user_valid_subscription()
  -> has_transcription_credits()
  -> hard-coded plan-family bounded/unlimited checks

UsageLimitPopupView
  -> Upgrade navigates to Account & Plan
  -> Bring your own keys navigates to Advanced
  -> dismiss closes popup
```

S-18 keeps the trial and managed-access gates, removes paid-overage and BYOK bypasses, maps fair-use class from normalized entitlement, and makes disabled mode's primary action Skip/dismiss without granting access.

### Usage APIs planned for deletion

`routers/users.py` still exposes the detailed GET `/v1/users/me/usage`, detailed LLM-usage reads/top-features, personal self-report, retained `/v1/users/me/usage-quota`, and retained total managed-cost recording/read. The target deletes only the unused detailed/public surfaces and keeps the underlying server-recorded counters consumed by subscription usage, quota, fair use, support, Chat, PTT, and Account UI.

## 7. Complete caller and dependency inventory

Inventory must be refreshed after S-07/S-08 integration. Current confirmed owners are:

| Layer | Current files/symbols | S-18 disposition |
|---|---|---|
| macOS paywall | `UsageLimitPopupView.swift`; `DesktopHomeView` `onUpgrade`, `onDismiss`, `onBringYourOwnKeys`; `AppState+TrialPaywall.swift`; `OmiApp.swift`; `TrialBannerService.swift` | Keep gates; disabled-mode Skip/dismiss; remove BYOK action after S-07; active-mode navigation may return later |
| macOS billing UI | `SettingsPage.swift`; `SettingsContentView+AccountBilling.swift`; `SettingsContentView+BillingHelpers.swift`; `BillingWebFlow.swift` | Keep current plan, usage, rich active-mode cards, hosted sheet, polling, Manage/Refresh; delete legacy/promo/overage/fallback/custom-upgrade/local-simulator state |
| macOS quota callers | `FloatingBarUsageLimiter.swift`; `ChatProvider.swift`; `AgentBridge.swift`; PTT/managed-access callers; `AppState` sticky paywall | Keep and adapt normalized plan/quota copy without weakening fail-open local vs server-authoritative enforcement |
| macOS API/contracts | `APIClient+People.swift`; `APIClient+Settings.swift`; `Generated/OmiApi.generated.swift` | Adapt subscription/checkout/portal contracts; delete duplicate, overage, upgrade, Stripe/legacy and detailed-usage bindings |
| macOS automation/E2E | `DesktopAutomationBridge.subscription_snapshot`; `usage_limiter_snapshot`; `DesktopAutomationSecondaryActionTests`; `e2e/flows/plan-usage.yaml`; `omi-ctl` Settings Account route | Retain and extend snapshots to prove billing availability/Skip and absence of checkout calls |
| backend routing | `main.py`; `routers/payment.py`; `routers/users.py`; `routers/chat.py`; `routers/desktop_chat.py`; `routers/listen/runtime.py` | Replace provider route/adapter, adapt subscription response, preserve quota/listen consumers, delete rejected routes |
| backend domain | `models/users.py`; `utils/subscription.py`; `utils/fair_use.py`; `utils/overage.py`; `utils/stripe.py`; `utils/executors.py` | Create one normalized catalog/projection/availability boundary; delete legacy plans, overage, Stripe, and Stripe executor naming after callers move |
| persistence/cache | `database/users.py` customer/subscription helpers; Firestore `users/{uid}.subscription`; LLM and user-usage stores; Redis subscription/trial/fair-use caches | Adapt customer/subscription fields and reverse lookup; add durable webhook idempotency/ordering metadata; preserve usage stores and retained invalidations |
| account deletion | `services/users/account_deletion.py`; its service/unit/E2E tests and billing failure markers | Adapt only provider cancellation behind S-08's claimed worker; preserve failure/retry/auth-delete ordering |
| rejected side effects | billing webhook cloud conversation/memory/action-item unlocks and personalized paid notification | Do not port to Dodo; remove S-18 call sites, leave helper-wide deletion to owning later slice where shared |
| route/OpenAPI | `route_policy_manifest.yaml`; `route_policy_legacy_missing_routes.txt`; `scripts/export_openapi.py`; `scripts/route_policy_inventory.py`; `scripts/check_response_model_coverage.py`; `scripts/generate_swift_openapi_types.py` | Register Dodo/retained payment routes, remove deleted routes/baseline exceptions, regenerate non-Windows Swift contract |
| dependencies | `requirements.txt`; `openapi-requirements.txt`; `pylock.toml`; `pylock.runtime.toml`; macOS lockfiles; pusher requirements/lock only if runtime import proves a caller | Add pinned Dodo SDK where imported; remove Stripe only after parity; do not inspect or change `pylock.windows.toml` |
| runtime config | backend env templates; `deploy/runtime_env.yaml`; backend/pusher/backend-listen charts; deployment-setting classification; backend workflows consuming those manifests | Add default disabled mode and classify Dodo secrets/config only on the canonical billing backend; remove Stripe from every service, including services that should never have received it |
| startup/support/docs | `main.py` startup Stripe validation; `scripts/support/find_stripe_entitlement_mismatches.py`; `backend/AGENTS.md`; `FORK.md` | Replace startup policy with local mode validation; delete Stripe-only repair script unless a retained Dodo incident proves a new support tool; document disabled/activation modes |
| tests | `test_available_plans_resilience.py`, `test_chat_quota.py`, `test_delete_account_stripe_cancel.py`, account-deletion tests, fair-use tests, LLM-usage tests, payment promo/reactivation/webhook tests, subscription plans/restructure/wire tests, trial tests; Swift routing, decoder, catalog-merger, plan-presentation, limiter, paywall, automation tests | Rewrite through production seams; delete tests exclusive to deleted behavior; keep regression meaning for retained behavior |
| transitive test/tool residue | Import-isolation stubs and comments in memory, voice, folder, action-item, account-deletion and E2E tests; `select_backend_unit_tests.py`; `pyrightconfig.json`; `services/users/__init__.py` | Remove/rename only Stripe bootstrap stubs, selectors, exclusions and comments after the dependency/import chain disappears; do not rewrite the unrelated behavior those harnesses protect |
| non-billing homonyms | `models/trend.py` company option **Stripe**; `TaskAssistantSettings.swift` finance/browser keyword **Stripe**; generic redaction coverage for `sk_live_...`-shaped secrets | Keep user-content/company vocabulary and generic secret redaction. These are not provider integration. Remove only the billing-specific Settings search keyword in `SettingsSidebar.swift` |
| local storage | No GRDB billing/subscription authority or billing background job was found; Mac billing state is ephemeral/view state plus paywall `UserDefaults` | Do not add a local subscription mirror. Backend Firestore projection remains authoritative |
| historical artifacts | release changelogs and Git history | Preserve history; exclude from residue claims unless executable/configured |

No Windows source, generated client, package lock, installer, workflow, or test is in scope.

## 8. Behavior classification

| Category | Behavior |
|---|---|
| **KEEP AS IS** | Three-day trial and default-off trial flag; authenticated subscription/trial/quota reads; current-plan and usage cards; loading/error/Refresh; embedded hosted-page sheet mechanics; eight-by-one-second reconciliation bound; managed subscriber access; server-recorded usage; Account/Chat/PTT limiter cooperation; fail-open local snapshot behavior with backend authoritative enforcement; account-deletion billing safety; 30-hour ceiling; Firebase identity/session boundary. |
| **ADAPT** | Provider client, customer/product/offer/subscription/webhook/checkout/portal/cancellation models; Stripe fields to normalized Dodo projection; rich server catalog; success/cancel URL identity; current-period/cancel display; cache invalidation; fair-use bounded/unlimited property; startup/runtime/dependency/config/docs; MVP paywall primary action to Skip under disabled billing; active-mode action back to hosted Dodo checkout. |
| **DELETE** | Stripe SDK/module/imports/executor names/IDs/env/secrets/routes/tests/support script; Omi legacy plan migration and deprecation card/fields; promotion; local checkout simulator; custom upgrade/schedule/proration; reactivation; direct customer cancel route with no retained caller; duplicate catalog endpoint/request/fallback/merger; overage; paid quota bypass; BYOK/free-plan bypass; detailed usage/LLM usage reads and personal self-report; rejected billing-triggered cloud unlock/notification side effects; exclusive generated bindings/route-policy/docs/config. |
| **SIMPLIFY AFTER** | Collapse catalog and subscription reads into `/v1/users/me/subscription`; make one billing deep module own runtime mode, catalog mapping, Dodo calls, webhook normalization, and projection; let hosted portal own paid customer changes; reduce Mac billing state to server response + one active flow + bounded poll; use one explicit entitlement policy for quota and fair use. |
| **OUT OF SCOPE / DEFERRED** | New onboarding step/sequence (S-17 unless ledger changes); managed AI provider portfolio (S-07); content-localization/fair-use enforcement beyond the normalized property (S-20); remaining shell navigation (S-21); deletion of whole rejected product helpers/readers not exclusively billing-owned (S-23); Cloud Run/Secret Manager/IAM resource creation and deploy foundation (S-27); signed/release validation (S-29/S-31); Dodo dashboard/product/collection/webhook creation, credentials, test transaction, production activation, live Stripe-resource decommission; Windows. |

## 9. Retained behavioral invariants

1. Disabled mode makes a transaction structurally impossible: no Dodo client construction, no provider request, no checkout/portal URL, no customer/subscription write, and no paid entitlement mutation.
2. Skip is not success. It neither clears `isPaywalled` nor changes subscription, trial, quota, usage, fair-use, or managed-access state.
3. The backend remains authoritative. Mac optimistic question increments are presentation only; backend Chat/PTT/listen admission uses server-recorded usage and the normalized active subscription.
4. Trial duration remains three days and `TRIAL_PAYWALL_ENABLED` remains false by default. Billing mode does not silently enable the trial paywall.
5. All plans, including paid plans after activation, stop at their included Chat allowance. There is no overage charge or paid bypass.
6. Normal paid PTT uses product-managed short-lived provider credentials. Personal keys never grant or substitute for subscription entitlement.
7. Only a verified, mapped, active Dodo subscription grants paid access. Checkout completion pages, Skip, portal launch, customer existence, or payment events alone do not.
8. A cancelled-at-period-end subscription retains access only through the authoritative access-end timestamp and displays **Access ends**. Immediate cancelled/failed/expired/on-hold state cannot remain paid unless the product contract explicitly maps it.
9. Duplicate or stale Dodo webhooks are idempotent and monotonic; they cannot resurrect a deleted account or replace a newer active subscription with an older terminal event.
10. The Mac never receives a provider API key or webhook secret and never submits arbitrary product IDs. It submits only an offer identity emitted by the authenticated subscription response.
11. Hosted checkout stays in the retained WKWebView; portal stays in the default browser. Card/payment data never enters application UI, logs, analytics, or persistence.
12. Reconciliation remains bounded to eight reads at one-second intervals and performs one success refresh; cancellation/dismissal stops it.
13. Account deletion cannot erase a possibly billable Dodo principal until provider cancellation is confirmed; disabled principals with no Dodo subscription require no provider call.
14. Detailed usage routes can disappear only after every retained server-side writer/reader used by quota, billing, total cost, fair use, support, Chat, and PTT is proven intact.
15. Provider responses, secrets, raw PII, card data, customer email, and webhook bodies are not logged. Existing sanitizer and fallback telemetry primitives are used.

## 10. Target authority and ownership model

### Runtime mode

One typed `BillingMode` parser owns the three legal values. `disabled` is the checked-in/default template value. `dodo_test` and `dodo_live` fail startup/local preflight unless all mode-specific keys and a complete catalog mapping exist. Partial configuration is an error, never an implicit fallback to disabled or live.

The authenticated subscription response exposes a provider-neutral capability such as:

```text
billing_availability:
  checkout_enabled: false
  portal_enabled: false
  presentation: skip
```

The public contract need not expose test/live or a secret-bearing provider detail. Active-mode tests assert that the capability changes only after configuration validation. Disabled-mode transaction endpoints return a typed non-2xx `billing_disabled`; they never return a fake URL or fake active plan.

### Catalog and entitlement

One backend `BillingCatalog` owns:

- stable internal plan and offer identities sent to the Mac;
- display/interval ordering and provider-sourced price presentation;
- the exact configured Dodo product ID for each offer;
- included Chat allowance/unit and managed speech allowance;
- one explicit `fair_use_class = bounded | unlimited` property;
- plan eligibility and active/terminal provider-status mapping.

The Mac renders the server response and sends back its offer identity. It does not maintain a fallback catalog, reconstruct titles, know Dodo product IDs, or infer entitlement from price/copy. Product IDs and commercial details remain configuration inputs, not synthetic defaults.

### Provider adapter and projection

One deep billing module hides the Dodo SDK and presents narrow operations:

```text
create_checkout(uid, offer_id, return_url, cancel_url)
create_portal(uid, return_url)
cancel_for_account_deletion(uid, dodo_subscription_id)
verify_and_normalize_webhook(raw_body, standard_headers)
project_subscription(normalized_event)
```

Firestore remains the runtime entitlement authority between webhooks. The normalized projection stores the internal plan/offer, status, access-period bounds, `cancel_at_next_billing_date`, Dodo customer/subscription/product identities required for provider reconciliation, provider update ordering metadata, and the explicit entitlement policy. It contains no Stripe alias fields.

A durable webhook receipt keyed by `webhook-id` supplies idempotency. Projection and receipt are committed atomically where the existing database abstraction permits; an update failure returns non-2xx so Dodo retries. Ordering uses the provider's authoritative resource update/version timestamp confirmed from a real fixture; if the payload lacks a safe ordering field, the affected webhook cycle stops and uses a documented Dodo retrieve-before-project strategy rather than guessing precedence.

### UI ownership

`SettingsContentView` owns presentation only. It consumes billing availability, current projection, rich offers, and usage/quota. `BillingWebFlow` owns hosted-page navigation/completion policy. `FloatingBarUsageLimiter` owns local presentation/preflight only. S-17 owns any onboarding transition. No local database becomes subscription authority.

## 11. Ordered TDD cycles

Each cycle is vertical: introduce one behavioral RED through a production seam, make the minimum implementation GREEN, then delete only the behavior made unnecessary by that GREEN. Do not write all tests first or organize cycles by file.

### Cycle 1 — disabled MVP: Skip with a hard no-transaction boundary

- **Behavioral RED:** Through the subscription API plus production Mac presentation policy, assert that default/missing provider credentials produce `checkout_enabled=false`, the visible usage-limit primary label is exactly `Skip`, invoking it dismisses/advances only through the supplied UI callback, and a spy provider receives zero checkout/portal calls. Assert subscription/trial/quota/paywall state is unchanged. Add the main error test: direct authenticated checkout/portal calls fail non-2xx with typed `billing_disabled` and no provider construction.
- **Why RED now:** Stripe routes are active when configured; subscription response has no billing capability; `UsageLimitPopupView` says Upgrade and routes to Account & Plan; BYOK remains visible at this baseline.
- **Minimum GREEN:** Add typed runtime-mode/config validation with checked-in default `disabled`; add provider-neutral billing availability to `/v1/users/me/subscription`; make transaction handlers guard before adapter construction; adapt `UsageLimitPopupView`/`DesktopHomeView` to Skip/dismiss in disabled mode and record the existing component fallback diagnostic without PII. Consume S-07's removed BYOK action rather than deleting it twice.
- **Retained protection:** Trial metadata/gates, free subscription, current usage, server quota enforcement, `TRIAL_PAYWALL_ENABLED=false`, and existing dismiss behavior.
- **Expected changes:** Billing config/domain module, payment/subscription response models and route, Swift DTO/presentation, generated contract, paywall and routing tests, environment templates, backend/desktop guide notes.
- **Focused verification:** focused backend billing-mode/subscription tests; Swift billing-availability, `UsageLimitPopupView`, API decode/routing, and paywall tests; hermetic assertion that the fake adapter call list is empty.
- **Deletion enabled:** Active purchase CTA and BYOK branch from the disabled presentation; no Stripe code is deleted yet because active-mode parity does not exist.
- **Stop condition:** Stop the literal onboarding assertion if G4 is unresolved. Keep the verified post-onboarding Skip/dismiss path and do not invent a screen.

### Cycle 2 — normalized Dodo catalog and subscription projection

- **Behavioral RED:** Given a hermetic configured catalog and representative Dodo subscription fixture, `/v1/users/me/subscription` returns one normalized active offer, periods/access end, cancellation flag, quota policy, and rich available plans; unknown product IDs or incomplete mappings grant no paid access and fail the active-mode preflight. Disabled mode still returns no actionable paid offer.
- **Why RED now:** Plan types, price IDs, presentation, legacy mappings, and limits are spread across `models/users.py`, `utils/subscription.py`, Stripe retrieval, and Mac fallback logic.
- **Minimum GREEN:** Introduce the single `BillingCatalog` and normalized subscription projection; map configured Dodo product IDs to internal offers and entitlement policy; adapt Firestore read/write helpers and `/v1/users/me/subscription`; keep provider price/catalog I/O behind the adapter and use only synthetic IDs in tests.
- **Retained protection:** Current plan/loading/error/status/price/interval/renewal/access-end/Refresh behavior; backend-owned quota and managed-access entitlement.
- **Expected changes:** Backend domain/models/database/users route, subscription tests/wire contract, Mac DTO/decoder/presentation tests, OpenAPI/generated Swift, configuration schema documentation.
- **Focused verification:** focused catalog mapping, unknown-product fail-closed, inactive/cancelled projection, subscription response, Swift decoder/presentation, and disabled-mode tests.
- **Deletion enabled:** Duplicate plan definitions and provider inference can be marked for Cycle 6 deletion only after all retained callers consume the normalized response.
- **Stop condition:** Stop activation values if commercial details are absent. The type/parser/failure tests may proceed; never commit invented plan IDs, names, prices, or allowances.

### Cycle 3 — signed, idempotent, monotonic Dodo webhook projection

- **Behavioral RED:** Send locally signed raw Dodo subscription events through the production FastAPI webhook seam. Valid active/updated/renewed/plan-changed/cancelled/failed/expired/on-hold fixtures update the normalized projection once; invalid/missing Standard Webhooks headers fail authentication; duplicate `webhook-id` is a no-op success; stale delivery cannot overwrite newer state; unknown product fails closed; deleted UID is not recreated; persistence failure returns non-2xx.
- **Why RED now:** `/v1/stripe/webhook` parses Stripe events/schedules and lacks Dodo signature/header/idempotency semantics.
- **Minimum GREEN:** Add the Dodo webhook route and adapter verification over exact raw bytes; normalize only retained subscription lifecycle events; add durable idempotency/ordering state and transactional projection; invalidate retained subscription/trial/quota/fair-use caches after a committed change.
- **Retained protection:** Webhook-driven entitlement, cache repair, stale-event protection, no deleted-user resurrection, and sanitized logs.
- **Expected changes:** Payment router/deep module, database abstraction, route policy, webhook tests/fixtures, response-model coverage and docs. Fixtures are derived from official schema, not hand-waved Stripe shapes.
- **Focused verification:** focused valid/invalid signature, duplicate, out-of-order, unknown-product, deleted-user, and persistence-failure tests through the FastAPI route.
- **Deletion enabled:** Stripe webhook event and schedule handlers plus rejected cloud-unlock/paid-notification call sites after Cycle 4/5 parity; helper-wide cleanup stays with S-23 where shared.
- **Stop condition:** Stop projection if no authoritative resource ordering field can be confirmed from the SDK/real test fixture; define retrieve-before-project behavior before GREEN.

### Cycle 4 — future active-mode hosted Dodo checkout and bounded reconciliation

- **Behavioral RED:** With `dodo_test` configuration and a controllable adapter, selecting a server-issued offer creates a Dodo checkout with the authenticated UID association and exact return/cancel URLs, opens the returned hosted URL in the retained sheet, intercepts only the exact completion URLs, and performs at most eight one-second subscription reads until the expected offer/product is active. Invalid/tampered offers, provider error, timeout, cancel, dismiss, and disabled mode never grant entitlement. No local completion request occurs.
- **Why RED now:** Checkout takes a Stripe price ID/promo, may reactivate locally, and calls the local success simulator before polling a Stripe price.
- **Minimum GREEN:** Change checkout request to the server-issued offer identity; use the async Dodo adapter to create a hosted checkout; adapt completion policy and expected-offer matching; retain the bounded poll and one success refresh; remove local simulation from the production path.
- **Retained protection:** WKWebView Close/new-window behavior, exact success/cancel interception, bounded reconciliation, quota/paywall refresh, and error messages.
- **Expected changes:** Payment route/models/adapter, Mac API/DTO/billing helpers/web flow, route policy/OpenAPI/generated Swift, checkout and navigation-policy tests, Dodo configuration docs.
- **Focused verification:** backend checkout core/error/tamper/disabled tests; Swift routing, hosted-flow policy, eight-read success/timeout/cancel tests using an injected clock/API seam rather than real sleeps.
- **Deletion enabled:** Promotion, reactivation response, local simulator, Stripe checkout construction, and raw provider price submission after GREEN; final deletion occurs in Cycle 6/10.
- **Stop condition:** Real Dodo network acceptance is blocked until G3 credentials/products exist. Hermetic GREEN cannot be described as sandbox parity.

### Cycle 5 — hosted portal and account-deletion cancellation

- **Behavioral RED:** An active Dodo customer obtains a hosted portal URL through the authenticated backend; a free/no-customer principal gets a bounded user-facing error; disabled mode makes no provider call. A claimed S-08 account-deletion worker cancels an active Dodo subscription before irreversible deletion, persists/retries uncertainty, proceeds without a provider call for no-subscription disabled principals, and fails closed for a possibly billable principal when provider configuration/cancellation is unavailable.
- **Why RED now:** Portal and deletion cancellation retrieve Stripe customer/subscription state, while custom upgrade/direct cancel behavior still exists.
- **Minimum GREEN:** Create Dodo portal sessions from the normalized customer ID; adapt Mac Manage launch; replace the provider-specific cancellation inside S-08's worker; preserve billing failure markers and deletion ordering.
- **Retained protection:** Manage/error UI, hosted browser, cancellation/access-end projection, account-deletion no-future-charge guarantee, and owner isolation.
- **Expected changes:** Provider adapter/payment route/account-deletion worker/database fields, Mac portal model/UI, service/unit/E2E tests, docs/contracts.
- **Focused verification:** portal active/free/disabled/error tests; account deletion no-subscription, active-cancelled, missing-config, provider-timeout, retry, account-switch/UID isolation tests; Swift Manage routing tests.
- **Deletion enabled:** Stripe customer helpers, direct cancellation route with no retained caller, custom paid plan change/cancel code; ordinary paid changes are now portal-owned.
- **Stop condition:** Stop and rebase if the integrated S-08 deletion worker seam differs. Real portal/cancellation acceptance remains blocked by G3.

### Cycle 6 — remove Omi legacy plans and custom billing behavior

- **Behavioral RED:** Through current-plan/catalog/checkout public seams, assert there is no Plan Retiring card, deprecated field, Omi/legacy title normalization, promotion input, reactivation response, custom paid upgrade request, second catalog fetch, fallback merger, or schedule/proration state; free-to-paid uses checkout only when active, paid users use Manage, and disabled MVP shows Skip/no purchase.
- **Why RED now:** All named legacy/custom paths and tests are live in the current checkout.
- **Minimum GREEN:** Move every retained caller to the Cycle 2-5 model, then delete the legacy plan enum/mapping/wire compatibility, deprecation UI/fields, promo, reactivation, upgrade/schedule logic, fallback catalog/merger, and second plan request.
- **Retained protection:** Current plan, rich future catalog, monthly/annual presentation, trial cards, active-mode checkout, hosted portal, and bounded refresh.
- **Expected changes:** `utils/subscription.py`, payment/users models/routes, Settings state/helpers/sections, API DTO/routes, generated contract, legacy/payment/catalog tests and docs.
- **Focused verification:** backend subscription response/catalog/checkout/portal tests; Swift decoder, plan presentation, API routing and Account & Plan tests; removed routes assert 404/405 as appropriate.
- **Deletion enabled:** GET `/v1/payments/available-plans`, POST `/v1/payments/upgrade-subscription`, direct subscription cancel route with no retained caller, and all exclusive response/request types.
- **Stop condition:** Stop if a refreshed non-Windows released caller proves a removed route contract is external; obtain an explicit contract decision rather than adding compatibility.

### Cycle 7 — hard-cap every plan and delete overage while retaining usage

- **Behavioral RED:** For representative free, bounded paid, and unlimited-fair-use paid projections, server Chat admission rejects usage at the included allowance with the existing typed limit behavior; Account usage card and shared Chat/PTT limiter show server snapshot/reset/warning; optimistic question increments remain local; disabled billing does not change quota. Assert overage endpoint/UI/models and paid bypass are absent.
- **Why RED now:** Paid/overage-enabled plans can continue beyond included allowance and the UI promises later overage billing.
- **Minimum GREEN:** Centralize allowance/unit in normalized entitlement, remove paid bypass and `utils/overage`, adapt quota copy/card, keep server writers and `/usage-quota`, and delete overage UI/state/request/route/models/tests.
- **Retained protection:** Account usage loading/progress/reset/warnings, shared limiter, server cost/question units, fail-open local behavior, managed Chat/PTT recording, and total managed cost.
- **Expected changes:** subscription/quota utility, Chat/desktop Chat callers, payment/users routes/models, overage utility, Settings/UI/API DTOs, quota/overage tests, docs/contracts.
- **Focused verification:** free/bounded/unlimited-at-cap backend tests through Chat and desktop Chat production handlers; Swift limiter/action/usage-card tests; POST failure leaves local optimistic behavior bounded; GET `/v1/payments/overage-info` fails closed.
- **Deletion enabled:** All overage code/config/tests and paid quota bypass.
- **Stop condition:** Exact numeric allowances remain blocked by G3; use only explicitly approved values. Do not derive limits from price or Dodo display copy.

### Cycle 8 — map Dodo entitlement class to fair-use thresholds

- **Behavioral RED:** The production fair-use evaluator consumes the normalized entitlement property and selects exactly 2/8/10 hours for bounded and 4/16/20 hours for unlimited, while preserving the separate 30-hour ceiling. Unknown/missing property fails to bounded/no-paid access rather than inspecting legacy plan names. Managed PTT/listen access still follows the valid active subscription.
- **Why RED now:** `utils/fair_use.py` hard-codes plan families and calls `is_paid_plan`/`has_transcription_credits` through legacy types.
- **Minimum GREEN:** Pass one explicit entitlement policy from the subscription/catalog projection into fair-use and managed-access checks; remove plan-name inference while retaining existing counters, locks, and ceiling.
- **Retained protection:** Exact review bands, separate ceiling, server-authoritative managed speech access, quota/fair-use persistence and clearing.
- **Expected changes:** Billing catalog/projection, subscription/fair-use utilities and callers, fair-use/managed-access tests, documentation for S-20.
- **Focused verification:** current fair-use plan-aware/upgrade tests rewritten behaviorally for bounded/unlimited/missing/terminal/account-switch states; managed PTT/listen admission tests.
- **Deletion enabled:** Legacy bounded/unlimited plan sets and duplicated entitlement inference.
- **Stop condition:** Stop if S-20 integrated a newer normalized property; consume its documented seam or agree owner order, never add a second property.

### Cycle 9 — remove unused detailed usage APIs and regenerate contracts

- **Behavioral RED:** Route-level tests assert GET `/v1/users/me/usage`, detailed LLM-usage GET/top-features, and personal self-report POST are absent while `/v1/users/me/usage-quota`, subscription monthly usage, server-recorded managed Chat/PTT count/cost, total managed cost, fair use, and Account usage snapshot still work. Generated Swift has no deleted bindings.
- **Why RED now:** The routes/models/tests remain registered even though the retained desktop billing surface consumes quota/subscription summaries instead.
- **Minimum GREEN:** Prove every retained store caller, remove only exclusive routes/models/helpers/tests/docs, update route policy/missing baseline and OpenAPI export exclusions, regenerate the non-Windows Swift client.
- **Retained protection:** All underlying managed-usage writers and retained aggregate readers, idempotency, quota, billing, fair use, LangSmith, and support/account summaries.
- **Expected changes:** Users router/models/database helpers only if exclusive, route tests/policy/OpenAPI scripts, generated Swift, API wrappers/tests and docs.
- **Focused verification:** focused route absence plus retained quota/total-cost/subscription usage/Chat/PTT writer tests; OpenAPI contract and route-policy inventory checks; generated-client freshness.
- **Deletion enabled:** IR-831/IR-835 exclusive API, test, generated, route-policy, and documentation residue.
- **Stop condition:** Stop deletion for any helper with a retained internal caller. Delete the public route independently and hand shared storage cleanup to S-23.

### Cycle 10 — remove Stripe and prove the interim repository/MVP checkpoint

- **Behavioral RED:** A repository/runtime acceptance test starts with `BILLING_MODE=disabled` and no Stripe or Dodo credentials, serves subscription/trial/quota, renders Skip, and proves zero transaction calls. Active mode with any missing key/catalog fails preflight. Residue checks find no executable/configured Stripe or Omi plan identifier outside history; deleted routes fail closed; all retained tests and generated contracts are current.
- **Why RED now:** Stripe imports/dependencies/env/chart/runtime/startup/docs/support tooling and identifiers remain throughout the checkout.
- **Minimum GREEN:** After Cycles 2-5 hermetic Dodo parity, delete `utils/stripe.py`, Stripe dependency/imports/executor/startup validation, customer/subscription fields/helpers, env/secrets/price IDs/charts/runtime/workflow inputs, support script and exclusive tests; add Dodo SDK/config classification only to the canonical billing backend; update `backend/AGENTS.md` and `FORK.md`; simplify the deep module and run closure checks.
- **Retained protection:** Disabled no-transaction MVP, all billing/trial/quota/managed-access behaviors, account deletion, active-mode fail-closed validation, and future Dodo adapter contracts.
- **Expected changes:** All remaining files identified by the refreshed Stripe/Omi/overage/usage inventories, non-Windows dependency locks, docs/config/manifests/tests/contracts.
- **Focused verification:** focused disabled startup, active missing-config, residue, route-absence, subscription/trial/quota, account deletion, webhook/checkout/portal adapter, Swift UI/routing/automation tests; then component suites and preflight in §§14-15.
- **Deletion enabled:** Final Stripe/Omi/overage residue and obsolete repair/config paths. No Stripe shim, alias, ignored env, or dormant route remains.
- **Stop condition:** Do not delete the last Stripe path until every retained provider behavior has hermetic Dodo coverage and disabled mode is end-to-end GREEN. Do not touch Windows or historical changelogs. A real Dodo transaction remains outside repository closure until separately authorized.

## 12. Cross-slice ownership and handoffs

| Slice | S-18 relationship | Owner rule |
|---|---|---|
| S-07 | Predecessor for managed provider credentials and BYOK deletion | S-18 consumes entitlement-to-managed-access; it does not restore or redesign provider credentials |
| S-08 | Predecessor for Firebase session/identity and claimed account-deletion worker | S-18 adapts only billing cancellation at the worker seam and preserves all S-08 ordering/failure contracts |
| S-17 | Owns exact onboarding graph, journal, Back/Skip, persistence, completion | S-18 supplies billing availability/presentation. A literal new onboarding paywall requires ledger/S-17 handoff before insertion |
| S-20 | Later fair-use/content enforcement owner | S-18 hands off one normalized `bounded|unlimited` property and current projection; S-20 must not reconstruct Dodo/catalog logic |
| S-21 | Later shell/navigation cleanup | S-18 owns Account & Plan billing/usage UI and its navigation target; S-21 removes only leftover shell residue |
| S-23 | Later rejected-product/detailed-reader cleanup | S-18 deletes billing-adjacent IR-831/IR-835 routes/generated bindings and rejected webhook side-effect calls. S-23 consumes that state and owns broader shared helper/product deletion |
| S-26 | Later final backend surface/config cleanup | S-18 supplies the final provider-specific route and application config shape; S-26 must not reintroduce duplicate services/routes |
| S-27 | Cloud Run, Secret Manager, IAM, deployment foundation and live infra owner | S-18 edits repository application config/templates/classification required for disabled/Dodo modes. S-27 or a separately authorized operation installs secrets/deploys/changes live resources |
| S-29/S-31 | Release/signed/live acceptance owners | S-18 supplies named-bundle and backend evidence; production-family rollout remains their gate |

Shared-file rule: after rebasing, if another slice changed `users.py`, subscription models, account deletion, Settings, route policy, OpenAPI generation, runtime env, or component guides, preserve its retained behavior and integrate at its exported seam. Never resolve an owner conflict by duplicating a model, endpoint, config key, or adapter.

## 13. Repository residue-search strategy

Run from repository root before implementation to pin the inventory, after each deletion cycle, and at final closure. Review every hit; do not blindly require zero in historical changelogs or this planning document.

```bash
# Provider/runtime residue (exclude Windows and historical release notes from executable claims)
rg -n -i 'stripe|STRIPE_|stripe_' \
  backend desktop/macos .github config FORK.md \
  --glob '!**/pylock.windows.toml' \
  --glob '!desktop/macos/changelog/**'

# Rejected plan/payment behavior
rg -n -i \
  'omi plan|Plan Retiring|deprecated|deprecation_message|promotion_code|upgrade-subscription|reactivat|subscription_schedule|proration|overage|completeLocalTestSubscriptionIfNeeded|complete-subscription|isLocalURL|fallbackPlanCatalog|SubscriptionPlanCatalogMerger' \
  backend desktop/macos .github config FORK.md \
  --glob '!**/pylock.windows.toml' \
  --glob '!desktop/macos/changelog/**'

# Removed routes and callers
rg -n \
  '/v1/payments/available-plans|/v1/payments/overage-info|/v1/payments/upgrade-subscription|/v1/users/me/usage|llm-usage|top-features' \
  backend desktop/macos .github config \
  --glob '!**/pylock.windows.toml'

# Retained billing/usage paths must still have production callers and tests
rg -n \
  'users/me/subscription|users/me/trial|usage-quota|FloatingBarUsageLimiter|BillingWebFlow|subscription_snapshot|has_transcription_credits|enforce_chat_quota|fair_use' \
  backend desktop/macos

# Dodo config must be canonical, disabled by default, and absent from unrelated services
rg -n 'BILLING_MODE|DODO_PAYMENTS_|dodo_' \
  backend desktop/macos .github config FORK.md \
  --glob '!**/pylock.windows.toml'

# No provider secrets or real identifiers in the diff
git diff --check
git diff --unified=0 -- . ':!bootstrap-scaffold/**' | \
  rg -n 'dodo_(live|test)|DODO_PAYMENTS_API_KEY=.+|DODO_PAYMENTS_WEBHOOK_KEY=.+' || true
```

Required interpretation:

- Code/config/test/generated hits for Stripe integration, Omi legacy plan behavior, overage, local simulator, custom upgrade/reactivation, or removed routes block repository closure. Generic user-content/company vocabulary and provider-shaped secret redaction are reviewed retained homonyms, not billing residue.
- `dodopayments` dependency and Dodo adapter/config/test hits are expected. Actual keys/customer/product IDs are forbidden.
- Any Dodo secret binding on pusher, backend-listen, a job, or another non-canonical service is a defect unless a refreshed runtime import/caller proves ownership.
- Historical changelogs and Git history are not rewritten.

## 14. Focused and component-level verification commands

Exact focused file/filter names should follow the tests created or retained by each cycle. Use repository-supported runners; do not claim these have passed in this planning document.

### Backend focused loop

```bash
cd desktop/macos
./scripts/dev-feedback.py --once python 'tests/unit/test_billing_mode.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_dodo_billing.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_dodo_webhook_behavioral.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_user_subscription_wire_contract.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_chat_quota.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_fair_use_plan_aware.py'
./scripts/dev-feedback.py --once python 'tests/services/users/test_account_deletion.py'
```

If the named new files are consolidated differently during implementation, record the exact discovered pytest paths. New backend tests must be in a runner-discovered location.

### macOS focused loop

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift 'BillingAvailabilityTests'
./scripts/dev-feedback.py --once swift 'APIClientRoutingTests'
./scripts/dev-feedback.py --once swift 'SubscriptionInfoDecoderTests'
./scripts/dev-feedback.py --once swift 'SubscriptionPlanPresentationTests'
./scripts/dev-feedback.py --once swift 'BillingWebFlowTests'
./scripts/dev-feedback.py --once swift 'FloatingBarUsageLimiterTests'
./scripts/dev-feedback.py --once swift 'NeoDesktopPaywallTests'
./scripts/dev-feedback.py --once swift 'PaywallClearResumeTests'
./scripts/dev-feedback.py --once swift 'DesktopAutomationSecondaryActionTests'
```

Tests must drive public production seams with injected provider/clock/API boundaries. Source-string assertions are allowed only as labelled static residue tripwires, never as webhook, quota, checkout, or UI behavioral proof.

### Route policy, OpenAPI, and generated non-Windows client

Run generation after route/model changes, then freshness checks:

```bash
cd backend
./scripts/openapi_runner.sh scripts/route_policy_inventory.py --check
./scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --write
./scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
./scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check
./scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
```

Do not generate or alter Windows artifacts.

### Component and repository gates

```bash
(cd backend && bash test.sh)
(cd desktop/macos && ./test.sh)
python3 bootstrap-scaffold/validate-requirements-ledger.py
make preflight
```

Also run the refreshed residue searches in §13 and `scripts/pr-preflight --suggest`; if implementation uses a `fix:` commit, follow the repository's failure-class declaration/validation contract.

## 15. Real named-bundle/user-path acceptance

Repository/MVP acceptance uses a disposable named bundle and local backend with `BILLING_MODE=disabled`; never launch, stop, or modify `/Applications/Omi.app` or `/Applications/Omi Beta.app`.

```bash
cd desktop/macos
OMI_APP_NAME=omi-dodo-billing BILLING_MODE=disabled OMI_SKIP_TUNNEL=1 ./run.sh
./scripts/omi-ctl health
./scripts/omi-ctl navigate settings account
./scripts/omi-ctl action subscription_snapshot
./scripts/omi-ctl action usage_limiter_snapshot
./scripts/omi-ctl log-path
```

The named-bundle acceptance record must show:

1. sign-in and the S-17 retained onboarding complete/skip paths still work;
2. current plan, trial, usage/quota, reset date, warning, Refresh, and error states render from the local backend;
3. triggering the usage-limit presentation shows a primary button exactly `Skip`; selecting it returns to the underlying screen and does not navigate to billing, clear the gate, or change entitlement;
4. a subsequent cost-bearing attempt is still admitted/rejected from the same authoritative quota/trial state;
5. Account & Plan has no actionable purchase or Manage control in disabled mode and makes no checkout/portal request;
6. direct checkout/portal requests fail with `billing_disabled`, and sanitized app/backend logs show no Dodo/Stripe network attempt, secret, URL, customer, or subscription creation;
7. switching accounts clears owner-scoped presentation and never shows another user's plan/usage;
8. relaunch preserves only legitimate auth/paywall state; it does not convert Skip into paid state;
9. retained managed Chat/PTT and trial/quota paths behave as their authoritative snapshots specify;
10. removed routes return 404/405 and removed generated calls cannot compile.

Add/extend a semantic automation action only if it drives production behavior and is registered in the existing automation/E2E lane. Do not create an on-demand dead probe.

Future Dodo test-mode acceptance is separately gated by G3. When authorized, use the same named bundle against a Dodo test account to prove hosted checkout, signed dashboard/CLI webhook delivery, expected-offer reconciliation, portal, plan change, cancellation/access-end, failure, account deletion, and zero Stripe identifiers. Only after test evidence is complete may an explicitly authorized production activation be attempted.

## 16. Repository closure versus separately authorized live operational closure

### Interim repository/MVP checkpoint in this change

The interim repository/MVP checkpoint is reached when all ten cycles are GREEN, component suites/preflight pass, disabled named-bundle acceptance passes, Stripe billing-integration and rejected-behavior residue is absent from executable/configured non-Windows surfaces, Dodo active modes fail closed without complete config, and no credentials or real identifiers were added. Retained generic company/content vocabulary and secret-shape redaction do not count as a billing integration.

This checkpoint intentionally ships **no transactions**. It is acceptable—and required—for Dodo checkout, portal, and webhook network acceptance to remain unexecuted because the user has withheld credentials.

This checkpoint does not mark S-18 complete against the deletion map. Final S-18 closure still requires the separately authorized Dodo test activation and later production activation below. The checkpoint is a short MVP stop on the way to that retained destination, not a replacement for it.

### Future test activation closure

Requires separate authorization and all test inputs in G3. It must:

1. install Dodo test credentials through the owned secret/deployment path, never the repository;
2. configure exact approved test products/collection/catalog mapping;
3. activate `BILLING_MODE=dodo_test` only on the test environment;
4. complete a provider-hosted test checkout and signed webhook replay/listener proof;
5. prove duplicate/out-of-order behavior, portal, plan change, cancellation, account deletion, quota and fair-use projection;
6. record sanitized provider/dashboard/backend/Mac evidence and confirm no Stripe/Omi plan identifiers.

### Future production activation closure

Requires another explicit authorization after test closure. It owns production Dodo products/collection/webhook, secrets, deployment, a bounded live transaction/cancellation proof, monitoring, and any live Stripe resource decommission. Code merge does not authorize any of these operations. Live Stripe customers/data are not migrated because this unreleased fork has no inherited Omi customers; if that fact changes, stop for a new migration decision.

## 17. Risks, ambiguities, and explicit stop points

| Risk/input | Why it matters | Safe work before it | Reopen evidence / stop point |
|---|---|---|---|
| No current onboarding paywall | S-17's exact graph cannot be silently expanded | Current usage-limit Skip/dismiss and billing-availability architecture | Ledger/S-17 identifies exact step and transition; otherwise do not add one |
| Commercial offer undefined | Plan names/prices/limits drive catalog, quota, and copy | Types, config validation, disabled UI, synthetic hermetic fixtures | Approved offer matrix and Dodo product mapping; never invent defaults |
| No Dodo credentials/resources | Real signatures, checkout, portal and cancellation cannot be proven | Adapter tests, locally signed fixtures, fail-closed modes, repository cleanup | Test keys/products/collection/webhook plus authorization; later production equivalents |
| Webhook ordering field uncertain until real SDK fixture | Stale delivery can revoke/restore access incorrectly | Header/signature/idempotency boundary and parser fixtures | Confirm authoritative version/update field or adopt retrieve-before-project; stop projection otherwise |
| Account deletion during provider outage | Erasing login before cancellation can leave charges | Preserve S-08 failure/retry markers and fake-provider tests | Cancellation confirmation required; never fail open |
| Disabled Skip mistaken for free paid access | UI dismissal could accidentally clear sticky paywall or grant managed credentials | Cycle 1 paired UI/backend negative tests | Any entitlement mutation/network call on Skip blocks merge |
| Default/live mode confusion | Dodo SDK defaults may be live if environment is omitted | Explicit `BillingMode`, no client in disabled, active config validation | Any implicit/default live environment blocks merge |
| Provider details or secrets in logs | Billing data is sensitive | Existing sanitizer, opaque fixture IDs, content-free diagnostics | Raw payload/key/customer/email/card hit blocks merge |
| S-07/S-08 drift | Current baseline still contains predecessor-era callers | Rebase/inventory gate | Stop rather than restoring BYOK or duplicating account/session/deletion logic |
| S-23 shared usage/product helpers | Deleting shared storage could break retained quota/support | Delete public/exclusive routes only | Retained caller means handoff to S-23, not opportunistic deletion |
| Dodo config on unrelated services | Current Stripe secrets leaked into pusher/listen manifests | Remove rejected bindings; add Dodo only to canonical backend | Runtime import/caller proof required for any exception |
| Windows lock/source noise | Destination excludes Windows | Exclude from searches/generation | Any required Windows edit is out of scope and stops for direction |

## 18. Final completion checklist

- [ ] `0d9934c` remains an ancestor after rebase; target HEAD, validator result, and refreshed inventories are recorded.
- [ ] S-07 managed-provider/BYOK and S-08 auth/account-deletion predecessor seams are integrated without duplication.
- [ ] Default `BILLING_MODE=disabled` requires no credentials and constructs no provider client.
- [ ] Disabled UI says **Skip**; Skip performs no network call, navigation to checkout, paid write, paywall clear, quota change, or entitlement grant.
- [ ] A literal new onboarding paywall was added only if the ledger and S-17 owner supplied its exact position/advance transition.
- [ ] Active modes fail startup/preflight on any missing/partial key, webhook key, environment, or catalog mapping; no implicit live default exists.
- [ ] One normalized backend catalog/projection owns offers, Dodo mapping, periods, cancellation, quota, and bounded/unlimited entitlement.
- [ ] Signed Dodo webhook behavior is authenticated, idempotent, monotonic, owner-safe, sanitized, and retry-correct through production seams.
- [ ] Future active-mode hosted checkout and eight-by-one-second reconciliation are behavior-tested without a local simulator.
- [ ] Hosted portal owns paid changes/invoices/payment methods/cancellation; account deletion confirms Dodo cancellation before irreversible deletion.
- [ ] Trial/current-plan/rich future catalog/usage card/limiter/managed-access/fair-use retained invariants pass.
- [ ] Omi legacy/deprecation, promotions, reactivation, custom upgrade/schedule/proration, duplicate catalog/fallback, overage, paid bypass, BYOK bypass, and local simulator are deleted.
- [ ] IR-831/IR-835 public detailed usage routes and exclusive models/tests/generated bindings/docs are deleted; retained writers/aggregates pass.
- [ ] Stripe SDK/module/imports/IDs/routes/env/secrets/config/charts/support scripts/tests and rejected side effects are absent from executable/configured non-Windows surfaces.
- [ ] Route policy, OpenAPI and generated Swift are regenerated/fresh; removed routes fail closed.
- [ ] Focused backend/Swift tests, backend suite, desktop suite, ledger validator, residue searches, `git diff --check`, and `make preflight` pass.
- [ ] Named bundle `omi-dodo-billing` proves disabled-MVP behavior, owner isolation, restart behavior, retained adjacent paths, and zero transaction calls.
- [ ] No product credentials, provider resources, deployments, transactions, production app processes, Windows artifacts, or historical changelogs were changed by repository implementation.
- [ ] The interim repository/MVP checkpoint is reported separately and is not described as final S-18 closure while Dodo test and production activation remain outstanding.
