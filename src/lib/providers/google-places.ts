import type { LeadProvider, LeadSearchParams, RawLead, BusinessCategory } from "./types";
import { CATEGORY_MAP } from "./categories";

const PLACES_TEXT_SEARCH = "https://places.googleapis.com/v1/places:searchText";

interface GooglePlace {
  id: string;
  displayName?: { text: string };
  formattedAddress?: string;
  nationalPhoneNumber?: string;
  internationalPhoneNumber?: string;
  websiteUri?: string;
  rating?: number;
  userRatingCount?: number;
  location?: { latitude: number; longitude: number };
  addressComponents?: Array<{
    longText: string;
    shortText: string;
    types: string[];
  }>;
}

/**
 * Paid provider backed by Google Places API (New).
 *
 * This is the "plug and play" upgrade path. The moment you set
 * GOOGLE_PLACES_API_KEY in the environment, the provider registry
 * (see index.ts) will offer this as an option â€” no other code changes.
 *
 * Returns ratings, review counts, and high-fill phone numbers that the
 * free OSM source can't match.
 */
export class GooglePlacesProvider implements LeadProvider {
  readonly key = "google_places";
  readonly label = "Google Places (Paid)";
  readonly requiresApiKey = true;

  private apiKey: string | undefined;

  constructor() {
    this.apiKey = process.env.GOOGLE_PLACES_API_KEY;
  }

  isConfigured(): boolean {
    return Boolean(this.apiKey);
  }

  async search(params: LeadSearchParams): Promise<RawLead[]> {
    if (!this.apiKey) {
      throw new Error(
        "Google Places isn't configured. Add GOOGLE_PLACES_API_KEY to enable it."
      );
    }

    const { categories, location, limit = 60 } = params;
    const all: RawLead[] = [];

    // One text search per category for cleaner categorization
    for (const cat of categories) {
      const def = CATEGORY_MAP[cat];
      if (!def) continue;
      const textQuery = `${def.googleKeyword} in ${location}`;
      const places = await this.textSearch(textQuery, Math.min(limit, 60));
      for (const p of places) {
        all.push(this.toLead(p, cat));
      }
    }

    return all;
  }

  private async textSearch(textQuery: string, pageSize: number): Promise<GooglePlace[]> {
    const res = await fetch(PLACES_TEXT_SEARCH, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": this.apiKey!,
        // Field mask keeps cost in the cheapest SKU tier possible
        "X-Goog-FieldMask": [
          "places.id",
          "places.displayName",
          "places.formattedAddress",
          "places.nationalPhoneNumber",
          "places.websiteUri",
          "places.rating",
          "places.userRatingCount",
          "places.location",
          "places.addressComponents",
        ].join(","),
      },
      body: JSON.stringify({ textQuery, pageSize }),
    });

    if (!res.ok) {
      const detail = await res.text();
      throw new Error(`Google Places error ${res.status}: ${detail}`);
    }
    const json = await res.json();
    return json.places ?? [];
  }

  private toLead(p: GooglePlace, category: BusinessCategory): RawLead {
    const comp = (type: string) =>
      p.addressComponents?.find((c) => c.types.includes(type))?.shortText ?? null;

    return {
      sourceId: `gplaces:${p.id.replace(/\//g, "_")}`,
      source: this.key,
      name: p.displayName?.text ?? "Unknown",
      category,
      phone: p.nationalPhoneNumber ?? null,
      website: p.websiteUri ?? null,
      email: null, // Places doesn't return email â€” enrichment step fills this
      address: p.formattedAddress ?? null,
      city: comp("locality"),
      state: comp("administrative_area_level_1"),
      postalCode: comp("postal_code"),
      lat: p.location?.latitude ?? null,
      lng: p.location?.longitude ?? null,
      rating: p.rating ?? null,
      reviewCount: p.userRatingCount ?? null,
    };
  }
}
