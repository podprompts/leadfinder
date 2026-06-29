import type { LeadProvider } from "./types";
import { OpenStreetMapProvider } from "./openstreetmap";
import { GooglePlacesProvider } from "./google-places";

/**
 * Provider registry.
 *
 * This is the ONE place that knows about concrete providers. The rest of the
 * app asks for a provider by key (or just takes the default) and codes against
 * the LeadProvider interface only.
 *
 * To go paid: set GOOGLE_PLACES_API_KEY in the environment. The Google provider
 * becomes "configured" automatically and can be selected in the UI. To make it
 * the default, change DEFAULT_PROVIDER_KEY below to "google_places".
 */

const registry: Record<string, LeadProvider> = {};

function register(p: LeadProvider) {
  registry[p.key] = p;
}

register(new OpenStreetMapProvider());
register(new GooglePlacesProvider());

export const DEFAULT_PROVIDER_KEY = "google_places";

export function getProvider(key?: string): LeadProvider {
  const provider = registry[key ?? DEFAULT_PROVIDER_KEY];
  if (!provider) {
    throw new Error(`Unknown lead provider: ${key}`);
  }
  return provider;
}

/** For the UI: list providers and whether each is ready to use */
export function listProviders() {
  return Object.values(registry).map((p) => ({
    key: p.key,
    label: p.label,
    requiresApiKey: p.requiresApiKey,
    configured: p.isConfigured(),
  }));
}

