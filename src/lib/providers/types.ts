/**
 * The lead data provider contract.
 *
 * Every data source (free OpenStreetMap, paid Google Places, paid Outscraper,
 * etc.) implements this same interface. The dashboard and API routes only ever
 * talk to this interface — never to a specific provider — so swapping the free
 * source for a paid one is a one-line change in `getProvider()`.
 */

export type BusinessCategory =
  | "handyman"
  | "general_contractor"
  | "hvac"
  | "plumber"
  | "electrician"
  | "roofer"
  | "landscaper"
  | "painter"
  | "locksmith"
  | "pest_control"
  | "cleaning"
  | "flooring";

export interface LeadSearchParams {
  categories: BusinessCategory[];
  /** Free-text location, e.g. "Phoenix, AZ" or "85281" */
  location: string;
  /** Center point — providers that support radius search use this */
  lat?: number;
  lng?: number;
  /** Search radius in miles */
  radiusMiles?: number;
  /** Soft cap on results requested from the provider */
  limit?: number;
}

export interface RawLead {
  /** Provider-stable ID so we can dedupe across runs (e.g. "osm:node/123") */
  sourceId: string;
  /** Which provider produced this record */
  source: string;
  name: string;
  category: BusinessCategory | string;
  phone?: string | null;
  website?: string | null;
  email?: string | null;
  address?: string | null;
  city?: string | null;
  state?: string | null;
  postalCode?: string | null;
  lat?: number | null;
  lng?: number | null;
  /** 0–5 rating if the source has it (paid sources do, OSM does not) */
  rating?: number | null;
  reviewCount?: number | null;
}

export interface LeadProvider {
  /** Stable provider key, e.g. "openstreetmap" | "google_places" */
  readonly key: string;
  /** Human label shown in the UI */
  readonly label: string;
  /** Whether this provider needs paid credentials to run */
  readonly requiresApiKey: boolean;
  /** True if credentials are present (or none needed) — UI shows status */
  isConfigured(): boolean;
  /** Run a search and return normalized leads */
  search(params: LeadSearchParams): Promise<RawLead[]>;
}
