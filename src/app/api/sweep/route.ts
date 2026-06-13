import { NextRequest, NextResponse } from "next/server";
import { getProvider } from "@/lib/providers";
import { scoreAndSort } from "@/lib/scoring";
import { checkPhone } from "@/lib/phone";
import { US_METROS } from "@/lib/metros";
import type { BusinessCategory, RawLead } from "@/lib/providers/types";

export const runtime = "nodejs";
export const maxDuration = 300; // sweeps take a while

interface SweepBody {
  categories: BusinessCategory[];
  radiusMiles?: number;
  provider?: string;
  /** Cap metros scanned (for a faster partial sweep). Default: all. */
  maxMetros?: number;
}

export async function POST(req: NextRequest) {
  let body: SweepBody;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  const { categories, radiusMiles = 25, provider: providerKey, maxMetros } = body;
  if (!categories?.length) {
    return NextResponse.json({ error: "Pick at least one category." }, { status: 400 });
  }

  const provider = getProvider(providerKey);
  if (!provider.isConfigured()) {
    return NextResponse.json(
      { error: `${provider.label} isn't configured yet.` },
      { status: 400 }
    );
  }

  const metros = maxMetros ? US_METROS.slice(0, maxMetros) : US_METROS;
  const all: RawLead[] = [];
  let metrosScanned = 0;
  let metrosFailed = 0;

  for (const metro of metros) {
    try {
      const leads = await provider.search({
        categories,
        location: metro.name,
        lat: metro.lat,
        lng: metro.lng,
        radiusMiles,
        limit: 200,
      });
      all.push(...leads);
      metrosScanned++;
    } catch {
      metrosFailed++;
      // keep going — one busy metro shouldn't kill the whole sweep
    }
    // be polite to free servers between calls
    await new Promise((r) => setTimeout(r, 300));
  }

  // Score + sort website-first
  const scored = scoreAndSort(all);

  // Dedupe across all metros
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
    location: `National sweep — ${metrosScanned} metros`,
    provider: provider.key,
    metrosScanned,
    metrosFailed,
    count: withPhoneCheck.length,
    leads: withPhoneCheck,
  });
}
