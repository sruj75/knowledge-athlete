import type { ProductionAdapterId } from "../adapters/interface.js";

export const MANAGED_PI_AUTH_ENV = "OMI_AUTH_TOKEN";

export function adapterIdForHarnessMode(
  harnessMode: string | undefined,
): ProductionAdapterId {
  if (harnessMode === undefined) return "pi-mono";
  switch (harnessMode) {
    case "piMono":
    case "pi-mono":
      return "pi-mono";
    default:
      throw new Error(`Unknown harness mode: ${harnessMode}`);
  }
}

export function managedPiIsActivated(
  authToken: string | undefined = process.env[MANAGED_PI_AUTH_ENV],
): boolean {
  return Boolean(authToken?.trim());
}

export function managedPiActivationError(): string {
  return "Managed Intentive authentication is unavailable. Sign in and try again.";
}
