# How Omi connected its desktop app to Cloud Run, Firebase, Firestore, and Redis

Date: 2026-08-29

## Short answer

There was no missing authentication design and no Cloud Run paywall.

Upstream Omi made its customer-facing Cloud Run service reachable from the
internet. The Mac app signed the user in with Firebase, sent the Firebase ID
token in the HTTP `Authorization` header, and the Python backend verified that
token before running protected routes. The backend—not the Mac—then accessed
Firestore and Redis.

The current Intentive repository already preserves that pattern. Its S-27
runtime manifest explicitly deploys both development and production with
`--allow-unauthenticated`, and its requirements say to keep Cloud Run internet
reachability while authenticating each route.

The problem appeared because the live `knowledge-athlete-dev` bootstrap was
manually created as a **private Cloud Run service**. That added a second Google
Cloud IAM gate in front of the existing Firebase gate. A normal Firebase user
does not have a Google Cloud service identity, so the request is rejected by
Cloud Run before the Python backend can inspect the Firebase token.

In plain English: we accidentally put a staff-only security guard outside a
door that already had the correct customer-login check.

## The upstream Omi request path

```text
Mac app
  |  signs the person in with Firebase
  |  sends: Authorization: Bearer <Firebase ID token>
  v
Publicly reachable Cloud Run service
  |  Cloud Run forwards the HTTP request to Python
  v
FastAPI route
  |  verifies the Firebase ID token and obtains the user's uid
  v
Backend service account --------> Firestore
Backend Redis client ------------> Redis
```

“Publicly reachable” does **not** mean “anyone can read user data.” It means
Cloud Run allows the request to reach the application. The application still
returns `401 Unauthorized` when a protected route has no valid Firebase token.
Google documents this as the normal custom-backend Firebase pattern: the client
sends its Firebase ID token over HTTPS and the server verifies it with the
Firebase Admin SDK.

## Evidence from the exact upstream source snapshot

The fork records upstream source commit
[`99e0e60be67a4f727ddfab4858184d75da2494a5`](https://github.com/BasedHardware/omi/tree/99e0e60be67a4f727ddfab4858184d75da2494a5).
At that exact commit:

1. Omi's development Cloud Run deployment passed
   [`--allow-unauthenticated`](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/.github/workflows/desktop_backend_auto_dev.yml#L201-L216).
2. Omi's production Cloud Run candidate deployment passed the same
   [`--allow-unauthenticated`](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/.github/workflows/desktop_backend_prod.yml#L281-L298)
   flag.
3. Omi's Mac code built an authorization value as
   [`Bearer <Firebase ID token>`](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/desktop/macos/Desktop/Sources/AuthService.swift#L2383-L2412).
4. Omi's backend required the authorization header on protected routes and
   called
   [`firebase_admin.auth.verify_id_token`](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/backend/utils/other/endpoints.py#L67-L114).
5. Omi's own operational runbook required successful
   [`public health responses`](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/docs/runbooks/desktop-backend-cloud-run-ownership.md#L88-L93)
   from development and production.
6. The backend initialized Firebase Admin using a local/emulator credential,
   an explicitly supplied service-account credential, or the hosted runtime's
   default Google identity. This was backend identity, not a Google Cloud
   identity that every desktop user had to possess.
7. Redis was also backend-only. The Python process read `REDIS_DB_HOST`,
   `REDIS_DB_PORT`, and `REDIS_DB_PASSWORD` and constructed the Redis client
   [inside the backend](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/backend/database/redis_db.py#L20-L30).

Omi had more than one backend plane at this snapshot: the Mac selected a normal
Python API URL and, for some desktop-specific work, a direct Cloud Run URL in
[`DesktopBackendEnvironment.swift`](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/desktop/macos/Desktop/Sources/DesktopBackendEnvironment.swift#L3-L7).
S-26 intentionally collapsed that duplicate topology into one canonical Python
backend. That is a simplification of the hosting layout; it does not require a
new customer-authentication design.

## What Intentive intentionally changed

### 1. One canonical backend

Intentive retained one Cloud Run backend rather than all of Omi's duplicate
services. This is the repository's explicit product decision
[`IR-008`](../bootstrap-scaffold/requirements-challenge.md#L53) and deployment
decision [`IR-839`](../bootstrap-scaffold/requirements-challenge.md#L657).

This change means the desktop has fewer backend destinations. It does not mean
the desktop should acquire Google Cloud IAM credentials.

### 2. Owned Firebase and Firestore

Intentive uses the owned `knowledge-athlete` Firebase/GCP project. The intended
boundary is still the upstream one:

- Firebase identifies the signed-in app user.
- FastAPI verifies the user's Firebase ID token.
- The attached Cloud Run runtime service account accesses Firestore through
  Application Default Credentials (ADC).
- Direct desktop Firestore access remains denied.

Google's current documentation describes these as two different identities:
the end user's Firebase ID token identifies the app user, while the Cloud Run
service identity lets backend code call Google APIs such as Firestore.

### 3. Upstash instead of Omi's private Redis network

Omi's runtime manifest connected Cloud Run to a private VPC/subnet and supplied
Redis host/password values to the backend. Intentive substituted a TLS-protected
Upstash Redis database because Google Memorystore charges for provisioned
capacity, even when it is not being used. The owner also chose one free Upstash
database for development and early MVP production until the product has
traction.

This is a real provider change, but the software boundary is the same:

```text
Mac -> Cloud Run backend -> Redis
```

It did **not** become:

```text
Mac -> Redis
```

Therefore Upstash did not cause the Cloud Run authentication problem. The only
related paywall/cost issue was choosing a Redis provider that could satisfy the
permanent-free operating constraint. Google states that Memorystore charges
begin when an instance is created and are based on provisioned capacity. Upstash
offers a limited free database. Neither rule requires private Cloud Run ingress.

## Where Intentive diverged by accident

The repository contract is already correct:

- Development declares
  [`--allow-unauthenticated: true`](../backend/deploy/runtime_env.yaml#L123).
- Production declares
  [`--allow-unauthenticated: true`](../backend/deploy/runtime_env.yaml#L361).
- The manifest validator requires that value
  [for both environments](../backend/scripts/validate-backend-runtime-env.py#L317-L330).
- The deployment workflows render those manifest flags and pass them to the
  Cloud Run deployment action.
- The requirements explicitly reject requiring every Mac caller to have a
  Google Cloud service identity. They say to
  [keep internet reachability and enforce authentication per route](../bootstrap-scaffold/requirements-challenge.md#L670).

The live bootstrap does not match that contract. A read-only inventory on
2026-08-29 showed:

- service: `knowledge-athlete-dev`
- project/region: `knowledge-athlete/us-west1`
- revision: `knowledge-athlete-dev-bootstrap-8c870c8`
- public invoker binding: absent
- unauthenticated `/v1/health`: Cloud Run `403`
- request with an owner's Google Cloud identity token: `200`

The tracked handoff documents then recorded this manual bootstrap as
intentionally private and created an unnecessary checklist item to decide how
the Mac should cross the extra IAM gate. That conclusion conflicts with both
upstream Omi and the already-merged S-27 contract.

This was an over-cautious deployment decision, not a product requirement, not a
Firebase limitation, and not a provider paywall.

## The monkey-see-monkey-do correction

The narrow correction is to return the development service to the pattern that
upstream Omi and Intentive's own manifest already specify:

1. Make the Cloud Run service publicly invokable at the Cloud Run layer by
   applying the existing `--allow-unauthenticated` deployment contract. Google
   currently also documents disabling the Invoker IAM check as its recommended
   public-service configuration.
2. Keep `/v1/health` intentionally public.
3. Keep protected FastAPI routes protected by their existing Firebase, webhook,
   metrics-secret, or Cloud Tasks OIDC dependencies.
4. Keep Firestore accessible only from the attached runtime identity/ADC path.
5. Keep Redis accessible only from the backend using its Secret Manager value
   and verified TLS connection.
6. Update `FORK.md` and `OWNER-PROVIDER-DECISIONS.md` so they no longer describe
   private Cloud Run IAM as an unresolved desktop design problem.

The acceptance checks should be behavioral:

| Request | Expected result |
|---|---|
| Public `GET /v1/health` | `200` from FastAPI |
| Protected route with no Firebase token | `401` from FastAPI, not a Cloud Run `403` |
| Protected route with an invalid/expired Firebase token | `401` from FastAPI |
| Protected route with a valid `knowledge-athlete` Firebase token | Success for that user |
| Authenticated backend Firestore operation | Uses the limited runtime service account |
| Backend Redis operation | Uses Upstash over verified TLS; desktop has no Redis credential |

This correction does not authorize a production deployment, a Beta/Stable
release, new paid resources, Apple membership work, or new provider secrets. It
only removes the accidental extra ingress lock from the existing development
bootstrap.

## Primary sources

- [Omi exact source snapshot](https://github.com/BasedHardware/omi/tree/99e0e60be67a4f727ddfab4858184d75da2494a5)
- [Omi development Cloud Run workflow](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/.github/workflows/desktop_backend_auto_dev.yml#L201-L216)
- [Omi production Cloud Run workflow](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/.github/workflows/desktop_backend_prod.yml#L281-L298)
- [Omi macOS Firebase bearer header](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/desktop/macos/Desktop/Sources/AuthService.swift#L2383-L2412)
- [Omi backend Firebase verification](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/backend/utils/other/endpoints.py#L67-L114)
- [Omi backend Redis client](https://github.com/BasedHardware/omi/blob/99e0e60be67a4f727ddfab4858184d75da2494a5/backend/database/redis_db.py#L20-L30)
- [Google Cloud: allow public Cloud Run access](https://docs.cloud.google.com/run/docs/authenticating/public)
- [Firebase: verify ID tokens on a custom backend](https://firebase.google.com/docs/auth/admin/verify-id-tokens)
- [Google Cloud: Cloud Run service identity and ADC](https://docs.cloud.google.com/run/docs/securing/service-identity)
- [Google Cloud: Memorystore for Redis pricing](https://cloud.google.com/memorystore/docs/redis/pricing)
- [Upstash Redis pricing](https://upstash.com/pricing/redis)
