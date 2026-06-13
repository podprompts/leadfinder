import { NextRequest, NextResponse } from "next/server";
import { getProvider } from "@/lib/providers";
import { geocode } from "@/lib/geocode";
import { scoreAndSort } from "@/lib/scoring";
import { checkPhone } from "@/lib/phone";
import type { BusinessCategory, RawLead } from "@/lib/providers/types";

export const runtime = "nodejs";
export const maxDuration = 300;

interface MultiSweepBody {
  categories: BusinessCategory[];
  cities: string[];
  radiusMiles?: number;
  provider?: string;
}

export async function POST(req: NextRequest) {
  let body: MultiSweepBody;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  const { categories, cities, radiusMiles = 25, provider: providerKey } = body;

  if (!categories?.length) {
    return NextResponse.json({ error: "Pick at least one category." }, { status: 400 });
  }
  if (!cities?.length) {
    return NextResponse.json({ error: "Add at least one city." }, { status: 400 });
  }

  const provider = getProvider(providerKey);
  if (!provider.isConfigured()) {
    return NextResponse.json(
      { error: `${provider.label} isn't configured yet.` },
      { status: 400 }
    );
  }

  const all: RawLead[] = [];
  const scanned: string[] = [];
  const failed: string[] = [];

  for (const city of cities) {
    try {
      // Geocode the city (needed for the free radius-based provider)
      const geo = await geocode(city);
      if (!geo) {
        failed.push(city);
        continue;
      }
      // Nominatim asks for max 1 req/sec — pause after geocoding
      await new Promise((r) => setTimeout(r, 1100));

      const leads = await provider.search({
        categories,
        location: city,
        lat: geo.lat,
        lng: geo.lng,
        radiusMiles,
        limit: 200,
      });
      all.push(...leads);
      scanned.push(city);
    } catch {
      failed.push(city);
    }
    // polite pause between cities for the Overpass servers
    await new Promise((r) => setTimeout(r, 400));
  }

  const scored = scoreAndSort(all);

  // Dedupe across cities
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
    location:
      scanned.length > 0
        ? `${scanned.length} cities: ${scanned.join(", ")}`
        : "No cities resolved",
    provider: provider.key,
    citiesScanned: scanned.length,
    citiesFailed: failed,
    count: withPhoneCheck.length,
    leads: withPhoneCheck,
  });
}
