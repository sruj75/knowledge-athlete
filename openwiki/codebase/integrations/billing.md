---
type: Codebase guide
title: Entitlement and disabled billing
description: Explain admission versus customer billing and the fail-closed billing provider boundary.
tags: [intentive, codebase]
resource: repo://backend/utils/billing
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T13:05:19.246Z
sources:
  - id: openwiki-source-a6f429ceca9782f6ae28e139
    resource: repo://backend/tests/unit/test_billing_mode.py
  - id: openwiki-source-d1f751da91f83454fabe5515
    resource: repo://backend/tests/unit/test_delete_account_billing_cancel.py
  - id: openwiki-source-45a66916bd16b1697eca50f8
    resource: repo://backend/utils/billing/config.py
  - id: openwiki-source-589974298fbdd0766d671404
    resource: repo://backend/utils/billing/factory.py
generated: { by: "codex", at: "2026-09-15T13:05:19.246Z" }
---
# Entitlement and disabled billing

The billing package separates configuration, provider effects and retained billing projections. `BillingConfig` is the entry boundary: an absent `BILLING_MODE` selects `disabled`; `dodo_test` and `dodo_live` require a complete credential, catalog and public-base-URL configuration.

## Disabled mode

Disabled mode supplies no API key, webhook key or catalog and advertises checkout and portal as unavailable. It does not construct the optional Dodo adapter. The service proves billing is active before the factory lazily imports that adapter. Tests deliberately supply malformed leftover Dodo configuration in disabled mode and block provider construction, proving this is more than a UI switch.

A retained legacy paid record needs special treatment during account deletion: the disabled runtime must not pretend it canceled a real subscription. Account deletion therefore retains its billing cancellation boundary and can report failure rather than making a false completion claim.

## Package ownership

| Module | Responsibility |
| --- | --- |
| `config.py` and `catalog.py` | Mode and complete configuration validation |
| `contracts.py` and `values.py` | Typed service/provider values |
| `service.py` and `factory.py` | Admission to optional provider effects |
| `provider.py` | Dodo API adapter |
| `store.py` and `projection.py` | Retained billing state and projections |

Authenticated product entitlement and billing presentation are different concepts. The current authored Beta constraint keeps customer billing disabled. The [billing activation handoff](../../INSTRUCTIONS.md#billing-activation-handoff) records owners, test/live authorization, evidence, cleanup and rollback prerequisites. The existence of working adapter code is not approval to activate it.

Follow [account lifecycle](../workflows/account-lifecycle.md) for deletion ordering and [backend architecture](../architecture/backend.md) for route composition.

## Source evidence

- [backend/utils/billing/config.py](../../../backend/utils/billing/config.py)
- [backend/tests/unit/test_billing_mode.py](../../../backend/tests/unit/test_billing_mode.py)
- [backend/utils/billing/factory.py](../../../backend/utils/billing/factory.py)
- [backend/tests/unit/test_billing_mode.py](../../../backend/tests/unit/test_billing_mode.py#L47-L86)
- [backend/tests/unit/test_billing_mode.py](../../../backend/tests/unit/test_billing_mode.py#L93-L100)
- [backend/tests/unit/test_delete_account_billing_cancel.py](../../../backend/tests/unit/test_delete_account_billing_cancel.py)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
