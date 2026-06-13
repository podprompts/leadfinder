import type { LeadProvider, LeadSearchParams, RawLead, BusinessCategory } from "./types";
import { CATEGORY_MAP } from "./categories";

// Multiple public Overpass endpoints — we try each, with retries, before
// giving up. The free servers are shared and frequently busy, so resilience
// here is what makes the free tier actually usable.
const OVERPASS_ENDPOINTS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
  "https://overpass.openstreetmap.ru/api/interpreter",
];

const MILES_TO_DEG = 1 / 69; // rough degrees of latitude per mile

interface OverpassElement {
  type: "node" | "way" | "relation";
  id: number;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
}

/**
 * Free provider backed by OpenStreetMap data via the Overpass API.
 * No API key, no account, no card. Coverage of small US businesses is
 * patchy and phone numbers are often missing — which is exactly why the
 * tool ranks website-having businesses to the top.
 */
export class OpenStreetMapProvider implements LeadProvider {
  readonly key = "openstreetmap";
  readonly label = "OpenStreetMap (Free)";
  readonly requiresApiKey = false;

  isConfigured(): boolean {
    return true; // always available
  }

  async search(params: LeadSearchParams): Promise<RawLead[]> {
    const { lat, lng, radiusMiles = 25, categories, limit = 200 } = params;

    if (lat == null || lng == null) {
      throw new Error(
        "OpenStreetMap search needs coordinates. Geocode the location first."
      );
    }

    const query = this.buildQuery(categories, lat, lng, radiusMiles, limit);
    const elements = await this.runQuery(query);

    return elements
      .map((el) => this.toLead(el, categories))
      .filter((l): l is RawLead => l !== null);
  }

  private buildQuery(
    categories: BusinessCategory[],
    lat: number,
    lng: number,
    radiusMiles: number,
    limit: number
  ): string {
    const radiusMeters = Math.round(radiusMiles * 1609.34);

    // Build a union of all OSM filters for the selected categories
    const filterClauses: string[] = [];
    for (const cat of categories) {
      const def = CATEGORY_MAP[cat];
      if (!def) continue;
      for (const filter of def.osmFilters) {
        // each filter like craft=plumber -> nwr["craft"="plumber"](around:R,lat,lng);
        const [k, v] = filter.split("=");
        filterClauses.push(
          `nwr["${k}"="${v}"](around:${radiusMeters},${lat},${lng});`
        );
      }
    }

    return `[out:json][timeout:25];
(
${filterClauses.join("\n")}
);
out center ${limit};`;
  }

  private async runQuery(query: string): Promise<OverpassElement[]> {
    const body = "data=" + encodeURIComponent(query);
    let lastError = "";

    // Two passes over all endpoints — busy servers often free up on retry
    for (let attempt = 0; attempt < 2; attempt++) {
      for (const endpoint of OVERPASS_ENDPOINTS) {
        try {
          const res = await fetch(endpoint, {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body,
          });
          if (res.status === 429 || res.status === 504) {
            lastError = `busy (${res.status})`;
            continue; // server overloaded — try next
          }
          if (!res.ok) {
            lastError = `status ${res.status}`;
            continue;
          }
          const json = await res.json();
          return json.elements ?? [];
        } catch (e) {
          lastError = e instanceof Error ? e.message : "network error";
          continue;
        }
      }
      // brief pause before the second pass
      if (attempt === 0) await new Promise((r) => setTimeout(r, 800));
    }
    throw new Error(
      `OpenStreetMap data servers are busy right now (${lastError}). Click Find leads again in a moment.`
    );
  }

  private toLead(
    el: OverpassElement,
    requestedCats: BusinessCategory[]
  ): RawLead | null {
    const tags = el.tags ?? {};
    const name = tags.name || tags["operator"] || null;
    if (!name) return null; // skip unnamed entries — useless as leads

    const coords =
      el.lat != null && el.lon != null
        ? { lat: el.lat, lng: el.lon }
        : el.center
        ? { lat: el.center.lat, lng: el.center.lon }
        : { lat: null, lng: null };

    // Best-effort category: match the tag back to one of our requested ones
    let matchedCat: string = requestedCats[0];
    for (const cat of requestedCats) {
      const def = CATEGORY_MAP[cat];
      if (!def) continue;
      const hit = def.osmFilters.some((f) => {
        const [k, v] = f.split("=");
        return tags[k] === v;
      });
      if (hit) {
        matchedCat = cat;
        break;
      }
    }

    const phone = tags.phone || tags["contact:phone"] || tags["contact:mobile"] || null;
    const website = tags.website || tags["contact:website"] || tags.url || null;
    const email = tags.email || tags["contact:email"] || null;

    // Assemble an address from OSM address tags
    const addrParts = [
      tags["addr:housenumber"],
      tags["addr:street"],
    ].filter(Boolean);
    const address = addrParts.length ? addrParts.join(" ") : null;

    return {
      sourceId: `osm:${el.type}/${el.id}`,
      source: this.key,
      name,
      category: matchedCat,
      phone,
      website,
      email,
      address,
      city: tags["addr:city"] || null,
      state: tags["addr:state"] || null,
      postalCode: tags["addr:postcode"] || null,
      lat: coords.lat,
      lng: coords.lng,
      rating: null, // OSM has no ratings
      reviewCount: null,
    };
  }
}
