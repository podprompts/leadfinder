/**
 * Free geocoding via OpenStreetMap Nominatim. No key, no card.
 * Converts "Phoenix, AZ" or "85281" into coordinates for radius search.
 *
 * Nominatim usage policy: max 1 request/second, requires a descriptive
 * User-Agent. We respect both.
 */

const NOMINATIM = "https://nominatim.openstreetmap.org/search";

export interface GeocodeResult {
  lat: number;
  lng: number;
  displayName: string;
}

export async function geocode(location: string): Promise<GeocodeResult | null> {
  const url =
    `${NOMINATIM}?format=json&limit=1&countrycodes=us&q=` +
    encodeURIComponent(location);

  const res = await fetch(url, {
    headers: {
      "User-Agent": "LeadFinder/1.0 (home-services lead tool)",
      "Accept-Language": "en-US",
    },
  });

  if (!res.ok) return null;
  const json = await res.json();
  if (!Array.isArray(json) || json.length === 0) return null;

  return {
    lat: parseFloat(json[0].lat),
    lng: parseFloat(json[0].lon),
    displayName: json[0].display_name,
  };
}
