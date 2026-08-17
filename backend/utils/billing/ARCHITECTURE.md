# Billing boundary

`config.py` owns the runtime mode and parses the server-owned catalog. The
default is `disabled`, which has no provider credentials and cannot construct a
provider client.

`catalog.py` maps opaque public offer IDs and provider product IDs to normalized
limits and the explicit `bounded` or `unlimited` entitlement policy. Commercial
names, product IDs, and allowances are deployment configuration; prices are
retrieved from Dodo and projected from the current provider subscription. The
repository contains no commercial defaults.

`service.py` guards every transaction-capable operation before it reaches
`provider.py`. `provider.py` is the only module that imports the Dodo SDK.
Subscription state stored in Firestore and returned to clients is normalized;
provider objects never cross this package boundary.

`store.py` is the async persistence port. Its Firestore adapter delegates to
`database/billing.py`, which owns the durable customer association and the
atomic projection-plus-webhook-receipt transaction.
