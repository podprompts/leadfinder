import { NextRequest, NextResponse } from "next/server";
import { getProvider } from "@/lib/providers";
import { geocode } from "@/lib/geocode";
import { scoreAndSort } from "@/lib/scoring";
import { checkPhone } from "@/lib/phone";
import type { BusinessCategory } from "@/lib/providers/types";

export const runtime = "nodejs";
export const maxDuration = 60;

interface SearchBody {
  categories: BusinessCategory[];
  location: string;
  radiusMiles?: number;
  provider?: string;
  limit?: number;
}

export async function POST(req: NextRequest) {
  let body: SearchBody;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  const { categories, location, radiusMiles = 25, provider: providerKey, limit } = body;

  if (!categories?.length) {
    return NextResponse.json({ error: "Pick at least one category." }, { status: 400 });
  }
  if (!location?.trim()) {
    return NextResponse.json({ error: "Enter a location." }, { status: 400 });
  }

  const provider = getProvider(providerKey);
  if (!provider.isConfigured()) {
    return NextResponse.json(
      { error: `${provider.label} isn't configured yet.` },
      { status: 400 }
    );
  }

  // Geocode for providers that need coordinates (the free OSM one does)
  let lat: number | undefined;
  let lng: number | undefined;
  let resolvedLocation = location;
  const geo = await geocode(location);
  if (geo) {
    lat = geo.lat;
    lng = geo.lng;
    resolvedLocation = geo.displayName;
  }

  let rawLeads;
  try {
    rawLeads = await provider.search({
      categories,
      location,
      lat,
      lng,
      radiusMiles,
      limit,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Search failed.";
    return NextResponse.json({ error: message }, { status: 502 });
  }

  // Score + sort (website-first)
  const scored = scoreAndSort(rawLeads);

  // Dedupe: same sourceId, or same name + same domain/phone (catches chains
  // and duplicate OSM entries like a business mapped as both node and way)
  const seen = new Set<string>();
  const deduped = scored.filter((l) => {
    const domain = l.website
      ? l.website.replace(/^https?:\/\//, "").replace(/^www\./, "").split("/")[0]
      : "";
    const keys = [
      l.sourceId,
      `${l.name.toLowerCase()}|${domain}`,
      l.phone ? `${l.name.toLowerCase()}|${l.phone}` : "",
    ].filter(Boolean);
    if (keys.some((k) => seen.has(k))) return false;
    keys.forEach((k) => seen.add(k));
    return true;
  });

  // Free phone validation pass (format/type) — annotate each lead
  const withPhoneCheck = deduped.map((lead) => {
    const check = lead.phone ? checkPhone(lead.phone) : null;
    return {
      ...lead,
      phoneValid: check?.valid ?? null,
      phoneType: check?.type ?? null,
      phoneFormatted: check?.formatted ?? lead.phone ?? null,
    };
  });

  return NextResponse.json({
    location: resolvedLocation,
    provider: provider.key,
    count: withPhoneCheck.length,
    leads: withPhoneCheck,
  });
}
