# ============================================================
# LeadFinder updater — overwrites the 6 changed files.
# Run from inside your leadfinder folder:
#   cd C:\Users\user\Documents\leadfinder
#   powershell -ExecutionPolicy Bypass -File .\update-leadfinder.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

# Safety: confirm we're in the right folder
if (-not (Test-Path 'package.json') -or -not (Test-Path 'src')) {
  Write-Host 'ERROR: Run this from inside the leadfinder folder (where package.json lives).' -ForegroundColor Red
  exit 1
}

function Write-FileSafe($path, $content) {
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  # Back up the existing file once
  if ((Test-Path $path) -and -not (Test-Path "$path.bak")) { Copy-Item $path "$path.bak" }
  Set-Content -Path $path -Value $content -NoNewline -Encoding UTF8
  Write-Host "  updated $path" -ForegroundColor Green
}

# ---- src/lib/enrich.ts ----
$content = @'
/**
 * Website enrichment.
 *
 * Given a business website, fetch the homepage (and a likely /contact page),
 * then extract VALIDATED emails, phone numbers, and social profiles. This is
 * free — we're fetching public pages we already have URLs for — and it's the
 * payoff of the website-first strategy: the site has the freshest, best-answered
 * contact number plus an email and socials the directory data never includes.
 *
 * Phones are validated with libphonenumber so tracking IDs, timestamps, and
 * placeholder junk (0000999999, 355-0000000, etc.) are filtered out.
 */

import { parsePhoneNumberFromString } from "libphonenumber-js";

const EMAIL_RE = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;
// Candidate phone strings: (480) 555-1234 / 480-555-1234 / +1 480 555 1234
const PHONE_RE = /(?:\+?1[\s.\-]?)?\(?\d{3}\)?[\s.\-]?\d{3}[\s.\-]?\d{4}/g;
// tel: links are the highest-confidence phone source on a page
const TEL_RE = /tel:([+\d().\s\-]{7,})/gi;

// Junk emails to ignore (tracking, assets, vendor noise)
const EMAIL_BLOCKLIST = [
  "example.com", "sentry.io", "wixpress.com", "godaddy.com", "squarespace.com",
  "schema.org", "w3.org", "googleapis.com", "gstatic.com", "cloudflare",
  ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".css", ".js",
];

// Role-based local parts that make the best outreach targets — surfaced first
const PRIORITY_LOCALPARTS = ["info", "contact", "sales", "hello", "office", "admin", "service"];

// Social platforms worth capturing for outreach
const SOCIAL_PATTERNS: Array<{ key: string; re: RegExp }> = [
  { key: "facebook", re: /https?:\/\/(?:www\.)?facebook\.com\/[A-Za-z0-9_.\-/]+/i },
  { key: "instagram", re: /https?:\/\/(?:www\.)?instagram\.com\/[A-Za-z0-9_.\-/]+/i },
  { key: "linkedin", re: /https?:\/\/(?:www\.)?linkedin\.com\/(?:company|in)\/[A-Za-z0-9_.\-/]+/i },
  { key: "twitter", re: /https?:\/\/(?:www\.)?(?:twitter|x)\.com\/[A-Za-z0-9_.\-/]+/i },
  { key: "youtube", re: /https?:\/\/(?:www\.)?youtube\.com\/[A-Za-z0-9_.\-@/]+/i },
];

export interface SocialProfiles {
  facebook?: string;
  instagram?: string;
  linkedin?: string;
  twitter?: string;
  youtube?: string;
}

export interface EnrichmentResult {
  url: string;
  reachable: boolean;
  emails: string[];
  phones: string[];
  socials: SocialProfiles;
  scannedContactPage: boolean;
  error?: string;
}

function cleanEmails(matches: string[]): string[] {
  const set = new Set<string>();
  for (const m of matches) {
    const lower = m.toLowerCase();
    if (EMAIL_BLOCKLIST.some((b) => lower.includes(b))) continue;
    // reject emails with absurd length or doubled dots (usually parse noise)
    if (lower.length > 60 || lower.includes("..")) continue;
    set.add(lower);
  }
  // Sort role-based addresses to the front — best outreach targets
  return [...set]
    .sort((a, b) => {
      const aPri = PRIORITY_LOCALPARTS.some((p) => a.startsWith(p + "@")) ? 0 : 1;
      const bPri = PRIORITY_LOCALPARTS.some((p) => b.startsWith(p + "@")) ? 0 : 1;
      return aPri - bPri;
    })
    .slice(0, 5);
}

/**
 * Validate + dedupe phones. Each candidate is parsed as a US number; only
 * genuinely valid numbers survive, normalized to one national format so
 * "(602) 944-4594" and "602-944-4594" collapse to a single entry.
 */
function cleanPhones(candidates: string[]): string[] {
  const valid = new Map<string, string>(); // e164 -> national format
  for (const raw of candidates) {
    const parsed = parsePhoneNumberFromString(raw, "US");
    if (!parsed || !parsed.isValid()) continue;
    // Skip obvious fakes: all-same-digit or sequential placeholder lines
    const digits = parsed.nationalNumber;
    if (/^(\d)\1+$/.test(digits)) continue; // 0000000000, 9999999999
    valid.set(parsed.number, parsed.formatNational());
  }
  return [...valid.values()].slice(0, 5);
}

function extractSocials(html: string): SocialProfiles {
  const socials: SocialProfiles = {};
  for (const { key, re } of SOCIAL_PATTERNS) {
    const m = html.match(re);
    if (m) {
      // trim trailing junk like quotes or closing tags
      let url = m[0].replace(/["'<>)].*$/, "");
      // skip bare platform roots (facebook.com/sharer, /plugins, etc.)
      if (/\/(sharer|plugins|share|intent|dialog)/i.test(url)) continue;
      (socials as Record<string, string>)[key] = url;
    }
  }
  return socials;
}

function normalizeUrl(raw: string): string {
  let url = raw.trim();
  if (!/^https?:\/\//i.test(url)) url = "https://" + url;
  return url;
}

async function fetchHtml(url: string, timeoutMs = 8000): Promise<string | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; LeadFinder/1.0; contact discovery)",
        Accept: "text/html",
      },
      redirect: "follow",
    });
    if (!res.ok) return null;
    const ct = res.headers.get("content-type") ?? "";
    if (!ct.includes("text/html")) return null;
    return await res.text();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function findContactLink(html: string, baseUrl: string): string | null {
  const linkRe = /<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let match: RegExpExecArray | null;
  while ((match = linkRe.exec(html)) !== null) {
    const href = match[1];
    const text = match[2];
    if (/contact/i.test(href) || /contact/i.test(text)) {
      try {
        return new URL(href, baseUrl).href;
      } catch {
        continue;
      }
    }
  }
  return null;
}

/** Pull phone candidates from both tel: links (high confidence) and body text */
function gatherPhoneCandidates(html: string): string[] {
  const out: string[] = [];
  let m: RegExpExecArray | null;
  const tel = new RegExp(TEL_RE);
  while ((m = tel.exec(html)) !== null) out.push(m[1]);
  out.push(...(html.match(PHONE_RE) ?? []));
  return out;
}

export async function enrichWebsite(rawUrl: string): Promise<EnrichmentResult> {
  const url = normalizeUrl(rawUrl);
  const result: EnrichmentResult = {
    url,
    reachable: false,
    emails: [],
    phones: [],
    socials: {},
    scannedContactPage: false,
  };

  const homeHtml = await fetchHtml(url);
  if (!homeHtml) {
    result.error = "Could not reach the site.";
    return result;
  }
  result.reachable = true;

  let combined = homeHtml;

  const contactUrl = findContactLink(homeHtml, url);
  if (contactUrl && contactUrl !== url) {
    const contactHtml = await fetchHtml(contactUrl);
    if (contactHtml) {
      combined += "\n" + contactHtml;
      result.scannedContactPage = true;
    }
  }

  result.emails = cleanEmails(combined.match(EMAIL_RE) ?? []);
  result.phones = cleanPhones(gatherPhoneCandidates(combined));
  result.socials = extractSocials(combined);

  return result;
}

'@
Write-FileSafe 'src/lib/enrich.ts' $content

# ---- src/lib/providers/openstreetmap.ts ----
$content = @'
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

'@
Write-FileSafe 'src/lib/providers/openstreetmap.ts' $content

# ---- src/app/api/search/route.ts ----
$content = @'
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

'@
Write-FileSafe 'src/app/api/search/route.ts' $content

# ---- src/components/Dashboard.tsx ----
$content = @'
"use client";

import { useState, useMemo } from "react";
import { CATEGORIES } from "@/lib/providers/categories";
import { downloadCsv } from "@/lib/csv";
import { saveSearch } from "@/lib/persistence";
import { isSupabaseConfigured } from "@/lib/supabase";
import styles from "./dashboard.module.css";

type Tier = "gold" | "website" | "phone" | "thin";

interface Lead {
  sourceId: string;
  source: string;
  name: string;
  category: string;
  phone?: string | null;
  phoneFormatted?: string | null;
  phoneType?: string | null;
  phoneValid?: boolean | null;
  website?: string | null;
  email?: string | null;
  address?: string | null;
  city?: string | null;
  state?: string | null;
  rating?: number | null;
  reviewCount?: number | null;
  score: number;
  tier: Tier;
  enrichedEmails?: string[];
  enrichedPhones?: string[];
  socials?: Record<string, string>;
  enriching?: boolean;
}

const SOCIAL_LABEL: Record<string, string> = {
  facebook: "FB",
  instagram: "IG",
  linkedin: "in",
  twitter: "X",
  youtube: "YT",
};

const TIER_META: Record<Tier, { label: string; cls: string }> = {
  gold: { label: "Website + Phone", cls: "tierGold" },
  website: { label: "Website", cls: "tierWebsite" },
  phone: { label: "Phone only", cls: "tierPhone" },
  thin: { label: "No contact", cls: "tierThin" },
};

export default function Dashboard() {
  const [selected, setSelected] = useState<Set<string>>(new Set(["handyman"]));
  const [location, setLocation] = useState("");
  const [radius, setRadius] = useState(25);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [leads, setLeads] = useState<Lead[]>([]);
  const [resolvedLocation, setResolvedLocation] = useState("");
  const [saveMsg, setSaveMsg] = useState("");
  const supabaseOn = isSupabaseConfigured();

  // filters
  const [onlyWebsite, setOnlyWebsite] = useState(false);
  const [onlyPhone, setOnlyPhone] = useState(false);
  const [search, setSearch] = useState("");

  function toggleCategory(key: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  async function runSearch() {
    if (selected.size === 0) { setError("Pick at least one category."); return; }
    if (!location.trim()) { setError("Enter a location."); return; }
    setError("");
    setLoading(true);
    setLeads([]);
    try {
      const res = await fetch("/api/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          categories: [...selected],
          location,
          radiusMiles: radius,
        }),
      });
      const data = await res.json();
      if (!res.ok) { setError(data.error ?? "Search failed."); setLoading(false); return; }
      setLeads(data.leads);
      setResolvedLocation(data.location ?? location);
    } catch {
      setError("Something went wrong running the search.");
    }
    setLoading(false);
  }

  async function enrichOne(sourceId: string) {
    const lead = leads.find((l) => l.sourceId === sourceId);
    if (!lead?.website) return;
    setLeads((prev) =>
      prev.map((l) => (l.sourceId === sourceId ? { ...l, enriching: true } : l))
    );
    try {
      const res = await fetch("/api/enrich", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ website: lead.website }),
      });
      const data = await res.json();
      setLeads((prev) =>
        prev.map((l) =>
          l.sourceId === sourceId
            ? {
                ...l,
                enriching: false,
                enrichedEmails: data.emails ?? [],
                enrichedPhones: data.phones ?? [],
                socials: data.socials ?? {},
                email: l.email ?? data.emails?.[0] ?? null,
              }
            : l
        )
      );
    } catch {
      setLeads((prev) =>
        prev.map((l) => (l.sourceId === sourceId ? { ...l, enriching: false } : l))
      );
    }
  }

  async function enrichAll() {
    const targets = filtered.filter((l) => l.website && !l.enrichedEmails);
    for (const t of targets) {
      // sequential to be polite to target sites
      await enrichOne(t.sourceId);
    }
  }

  async function saveToDb() {
    setSaveMsg("Saving…");
    try {
      const result = await saveSearch(
        {
          location: resolvedLocation || location,
          categories: [...selected],
          radiusMiles: radius,
          provider: "openstreetmap",
        },
        leads as never
      );
      if (result.saved > 0) {
        setSaveMsg(`Saved ${result.saved} leads`);
      } else {
        setSaveMsg("Sign in to save (no rows written)");
      }
    } catch {
      setSaveMsg("Save failed");
    }
    setTimeout(() => setSaveMsg(""), 4000);
  }

  const filtered = useMemo(() => {
    return leads.filter((l) => {
      if (onlyWebsite && !l.website) return false;
      if (onlyPhone && !l.phone) return false;
      if (search) {
        const q = search.toLowerCase();
        if (
          !l.name.toLowerCase().includes(q) &&
          !(l.city ?? "").toLowerCase().includes(q)
        )
          return false;
      }
      return true;
    });
  }, [leads, onlyWebsite, onlyPhone, search]);

  const stats = useMemo(() => {
    const total = leads.length;
    const withWebsite = leads.filter((l) => l.website).length;
    const withPhone = leads.filter((l) => l.phone).length;
    const gold = leads.filter((l) => l.tier === "gold").length;
    return { total, withWebsite, withPhone, gold };
  }, [leads]);

  return (
    <div className={styles.shell}>
      {/* Sidebar — search controls */}
      <aside className={styles.sidebar}>
        <div className={styles.brand}>
          <span className={styles.brandMark}>◆</span>
          <span className={styles.brandName}>Lead<strong>Finder</strong></span>
        </div>
        <p className={styles.brandTag}>Home services lead extraction</p>

        <div className={styles.field}>
          <label className={styles.label}>Trades</label>
          <div className={styles.chipGrid}>
            {CATEGORIES.map((c) => (
              <button
                key={c.key}
                onClick={() => toggleCategory(c.key)}
                className={`${styles.chip} ${selected.has(c.key) ? styles.chipOn : ""}`}
              >
                {c.label}
              </button>
            ))}
          </div>
        </div>

        <div className={styles.field}>
          <label className={styles.label}>Location</label>
          <input
            className={styles.input}
            placeholder="City, state or ZIP"
            value={location}
            onChange={(e) => setLocation(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && runSearch()}
          />
        </div>

        <div className={styles.field}>
          <label className={styles.label}>Radius — {radius} mi</label>
          <input
            type="range"
            min={5}
            max={50}
            step={5}
            value={radius}
            onChange={(e) => setRadius(Number(e.target.value))}
            className={styles.range}
          />
        </div>

        {error && <div className={styles.error}>{error}</div>}

        <button className={styles.searchBtn} onClick={runSearch} disabled={loading}>
          {loading ? "Searching…" : "Find leads"}
        </button>

        <p className={styles.sourceNote}>
          Source: OpenStreetMap (free). Drop in a Google Places key to upgrade
          to ratings and fuller phone coverage — no other changes needed.
        </p>
      </aside>

      {/* Main — results */}
      <main className={styles.main}>
        {leads.length === 0 && !loading && (
          <div className={styles.empty}>
            <div className={styles.emptyMark}>◆</div>
            <h2>Start with a trade and a place</h2>
            <p>
              Pick one or more trades, enter a city or ZIP, and pull a ranked
              list of businesses. The ones with a website rise to the top —
              they're the most reachable.
            </p>
          </div>
        )}

        {(leads.length > 0 || loading) && (
          <>
            <header className={styles.resultsHead}>
              <div>
                <h1 className={styles.resultsTitle}>
                  {loading ? "Searching…" : `${stats.total} leads`}
                </h1>
                {resolvedLocation && (
                  <p className={styles.resultsSub}>{resolvedLocation}</p>
                )}
              </div>
              <div className={styles.actions}>
                {supabaseOn && (
                  <button className={styles.ghostBtn} onClick={saveToDb} disabled={loading}>
                    {saveMsg || "Save to database"}
                  </button>
                )}
                <button className={styles.ghostBtn} onClick={enrichAll} disabled={loading}>
                  Enrich all websites
                </button>
                <button
                  className={styles.primaryBtn}
                  onClick={() => downloadCsv(filtered as never, "leads.csv")}
                  disabled={filtered.length === 0}
                >
                  Export CSV
                </button>
              </div>
            </header>

            {/* Stat strip */}
            <div className={styles.statStrip}>
              <Stat label="Total" value={stats.total} />
              <Stat label="With website" value={stats.withWebsite} accent />
              <Stat label="With phone" value={stats.withPhone} />
              <Stat label="Gold (both)" value={stats.gold} accent />
            </div>

            {/* Filter bar */}
            <div className={styles.filterBar}>
              <input
                className={styles.filterInput}
                placeholder="Filter by name or city…"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
              <label className={styles.check}>
                <input type="checkbox" checked={onlyWebsite}
                  onChange={(e) => setOnlyWebsite(e.target.checked)} />
                Has website
              </label>
              <label className={styles.check}>
                <input type="checkbox" checked={onlyPhone}
                  onChange={(e) => setOnlyPhone(e.target.checked)} />
                Has phone
              </label>
              <span className={styles.filterCount}>{filtered.length} shown</span>
            </div>

            {/* Table */}
            <div className={styles.tableWrap}>
              <table className={styles.table}>
                <thead>
                  <tr>
                    <th>Business</th>
                    <th>Tier</th>
                    <th>Phone</th>
                    <th>Website</th>
                    <th>Email</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((l) => {
                    const meta = TIER_META[l.tier];
                    return (
                      <tr key={l.sourceId}>
                        <td>
                          <div className={styles.bizName}>{l.name}</div>
                          <div className={styles.bizMeta}>
                            {[l.city, l.state].filter(Boolean).join(", ")}
                            {l.rating != null && ` · ★ ${l.rating}`}
                          </div>
                        </td>
                        <td>
                          <span className={`${styles.tier} ${styles[meta.cls]}`}>
                            {meta.label}
                          </span>
                        </td>
                        <td>
                          {l.phoneFormatted ?? l.phone ? (
                            <div>
                              <span>{l.phoneFormatted ?? l.phone}</span>
                              {l.phoneType && l.phoneType !== "unknown" && (
                                <span className={styles.phoneType}>{l.phoneType}</span>
                              )}
                            </div>
                          ) : (
                            <span className={styles.dim}>—</span>
                          )}
                          {l.enrichedPhones?.length ? (
                            <div className={styles.enriched}>
                              {l.enrichedPhones.map((p) => (
                                <span key={p} className={styles.enrichedItem}>{p}</span>
                              ))}
                            </div>
                          ) : null}
                        </td>
                        <td>
                          {l.website ? (
                            <a href={l.website} target="_blank" rel="noopener noreferrer"
                              className={styles.link}>
                              {prettyHost(l.website)}
                            </a>
                          ) : (
                            <span className={styles.dim}>—</span>
                          )}
                          {l.socials && Object.keys(l.socials).length > 0 && (
                            <div className={styles.socials}>
                              {Object.entries(l.socials).map(([k, url]) => (
                                <a key={k} href={url} target="_blank" rel="noopener noreferrer"
                                  className={styles.socialPill} title={url}>
                                  {SOCIAL_LABEL[k] ?? k}
                                </a>
                              ))}
                            </div>
                          )}
                        </td>
                        <td>
                          {l.email ? (
                            <a href={`mailto:${l.email}`} className={styles.link}>{l.email}</a>
                          ) : l.enrichedEmails?.length ? (
                            <a href={`mailto:${l.enrichedEmails[0]}`} className={styles.link}>
                              {l.enrichedEmails[0]}
                            </a>
                          ) : (
                            <span className={styles.dim}>—</span>
                          )}
                        </td>
                        <td>
                          {l.website && (
                            <button
                              className={styles.enrichBtn}
                              onClick={() => enrichOne(l.sourceId)}
                              disabled={l.enriching}
                            >
                              {l.enriching ? "…" : l.enrichedEmails ? "↻" : "Enrich"}
                            </button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </>
        )}
      </main>
    </div>
  );
}

function Stat({ label, value, accent }: { label: string; value: number; accent?: boolean }) {
  return (
    <div className={styles.stat}>
      <div className={`${styles.statNum} ${accent ? styles.statAccent : ""}`}>{value}</div>
      <div className={styles.statLabel}>{label}</div>
    </div>
  );
}

function prettyHost(url: string): string {
  try {
    return new URL(url.startsWith("http") ? url : "https://" + url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

'@
Write-FileSafe 'src/components/Dashboard.tsx' $content

# ---- src/components/dashboard.module.css ----
$content = @'
.shell {
  display: grid;
  grid-template-columns: 320px 1fr;
  min-height: 100vh;
  background: var(--black);
  color: #fff;
}

/* ---------- Sidebar ---------- */
.sidebar {
  border-right: 1px solid rgba(255,255,255,0.08);
  padding: 1.75rem 1.5rem;
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  position: sticky;
  top: 0;
  height: 100vh;
  overflow-y: auto;
}

.brand {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 18px;
}
.brandMark { color: var(--coral); }
.brandName { font-weight: 400; letter-spacing: -0.01em; }
.brandName strong { font-weight: 800; }
.brandTag {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: rgba(255,255,255,0.35);
  margin-top: -0.75rem;
}

.field { display: flex; flex-direction: column; gap: 0.5rem; }
.label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: rgba(255,255,255,0.5);
  font-weight: 600;
}

.chipGrid { display: flex; flex-wrap: wrap; gap: 6px; }
.chip {
  font-size: 12px;
  padding: 6px 11px;
  border-radius: 999px;
  border: 1px solid rgba(255,255,255,0.14);
  background: transparent;
  color: rgba(255,255,255,0.6);
  cursor: pointer;
  transition: all 0.12s;
}
.chip:hover { border-color: rgba(255,255,255,0.3); color: #fff; }
.chipOn {
  background: var(--coral);
  border-color: var(--coral);
  color: #fff;
  font-weight: 600;
}

.input {
  padding: 11px 13px;
  font-size: 14px;
  background: var(--black-3, #161616);
  border: 1px solid rgba(255,255,255,0.12);
  color: #fff;
  outline: none;
  transition: border-color 0.15s;
}
.input:focus { border-color: var(--coral); }
.input::placeholder { color: rgba(255,255,255,0.3); }

.range { accent-color: var(--coral); width: 100%; }

.searchBtn {
  margin-top: 0.25rem;
  padding: 13px;
  background: var(--coral);
  color: #fff;
  border: none;
  font-size: 12px;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  cursor: pointer;
  transition: background 0.12s;
}
.searchBtn:hover:not(:disabled) { background: var(--coral-light, #ff6a3d); }
.searchBtn:disabled { opacity: 0.5; cursor: default; }

.sourceNote {
  font-size: 11px;
  line-height: 1.6;
  color: rgba(255,255,255,0.35);
  border-top: 1px solid rgba(255,255,255,0.08);
  padding-top: 1rem;
  margin-top: auto;
}

.error {
  background: rgba(232,69,10,0.12);
  border: 1px solid rgba(232,69,10,0.3);
  color: #ff8a5c;
  font-size: 12px;
  padding: 9px 12px;
}

/* ---------- Main ---------- */
.main { padding: 1.75rem 2rem; min-width: 0; }

.empty {
  max-width: 380px;
  margin: 14vh auto 0;
  text-align: center;
}
.emptyMark { font-size: 2rem; color: var(--coral); margin-bottom: 1rem; }
.empty h2 { font-size: 1.4rem; font-weight: 700; margin-bottom: 0.6rem; }
.empty p { font-size: 0.9rem; color: rgba(255,255,255,0.5); line-height: 1.7; }

.resultsHead {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  margin-bottom: 1.5rem;
  gap: 1rem;
}
.resultsTitle { font-size: 1.6rem; font-weight: 800; letter-spacing: -0.02em; }
.resultsSub { font-size: 0.8rem; color: rgba(255,255,255,0.4); margin-top: 0.2rem; }

.actions { display: flex; gap: 0.6rem; }
.primaryBtn {
  padding: 10px 18px;
  background: var(--coral);
  color: #fff;
  border: none;
  font-size: 11px;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  cursor: pointer;
}
.primaryBtn:disabled { opacity: 0.4; cursor: default; }
.ghostBtn {
  padding: 10px 16px;
  background: transparent;
  border: 1px solid rgba(255,255,255,0.16);
  color: rgba(255,255,255,0.7);
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  cursor: pointer;
  transition: all 0.12s;
}
.ghostBtn:hover:not(:disabled) { border-color: var(--coral); color: #fff; }

.statStrip {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 1px;
  background: rgba(255,255,255,0.08);
  border: 1px solid rgba(255,255,255,0.08);
  margin-bottom: 1.5rem;
}
.stat { background: var(--black); padding: 1rem 1.25rem; }
.statNum { font-size: 1.8rem; font-weight: 800; letter-spacing: -0.02em; }
.statAccent { color: var(--coral); }
.statLabel {
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: rgba(255,255,255,0.4);
  margin-top: 0.2rem;
}

.filterBar {
  display: flex;
  align-items: center;
  gap: 1rem;
  margin-bottom: 1rem;
  flex-wrap: wrap;
}
.filterInput {
  flex: 1;
  min-width: 200px;
  padding: 9px 12px;
  background: var(--black-3, #161616);
  border: 1px solid rgba(255,255,255,0.12);
  color: #fff;
  font-size: 13px;
  outline: none;
}
.filterInput:focus { border-color: var(--coral); }
.check {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: rgba(255,255,255,0.6);
  cursor: pointer;
}
.check input { accent-color: var(--coral); }
.filterCount {
  font-size: 11px;
  color: rgba(255,255,255,0.35);
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.tableWrap {
  border: 1px solid rgba(255,255,255,0.08);
  overflow-x: auto;
}
.table { width: 100%; border-collapse: collapse; font-size: 13px; }
.table thead th {
  text-align: left;
  padding: 11px 14px;
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: rgba(255,255,255,0.4);
  font-weight: 600;
  border-bottom: 1px solid rgba(255,255,255,0.08);
  background: rgba(255,255,255,0.02);
}
.table tbody td {
  padding: 12px 14px;
  border-bottom: 1px solid rgba(255,255,255,0.05);
  vertical-align: top;
}
.table tbody tr:hover { background: rgba(255,255,255,0.02); }

.bizName { font-weight: 600; }
.bizMeta { font-size: 11px; color: rgba(255,255,255,0.4); margin-top: 0.2rem; }

.tier {
  display: inline-block;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  padding: 3px 8px;
  border-radius: 4px;
  white-space: nowrap;
}
.tierGold { background: rgba(232,82,26,0.18); color: #ff8a5c; border: 1px solid rgba(232,82,26,0.4); }
.tierWebsite { background: rgba(255,255,255,0.08); color: #fff; border: 1px solid rgba(255,255,255,0.18); }
.tierPhone { background: rgba(255,255,255,0.04); color: rgba(255,255,255,0.6); border: 1px solid rgba(255,255,255,0.1); }
.tierThin { background: transparent; color: rgba(255,255,255,0.3); border: 1px solid rgba(255,255,255,0.08); }

.link { color: #ff8a5c; text-decoration: none; }
.link:hover { text-decoration: underline; }
.dim { color: rgba(255,255,255,0.25); }

.phoneType {
  display: inline-block;
  margin-left: 6px;
  font-size: 9px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgba(255,255,255,0.4);
  border: 1px solid rgba(255,255,255,0.12);
  padding: 1px 5px;
  border-radius: 3px;
}

.enriched { margin-top: 4px; display: flex; flex-direction: column; gap: 2px; }
.enrichedItem { font-size: 11px; color: #7dd3a0; }

.enrichBtn {
  font-size: 11px;
  padding: 5px 10px;
  background: transparent;
  border: 1px solid rgba(255,255,255,0.16);
  color: rgba(255,255,255,0.7);
  cursor: pointer;
  transition: all 0.12s;
  white-space: nowrap;
}
.enrichBtn:hover:not(:disabled) { border-color: var(--coral); color: #fff; }
.enrichBtn:disabled { opacity: 0.5; cursor: default; }

/* ---------- Responsive ---------- */
@media (max-width: 880px) {
  .shell { grid-template-columns: 1fr; }
  .sidebar { position: static; height: auto; border-right: none; border-bottom: 1px solid rgba(255,255,255,0.08); }
  .statStrip { grid-template-columns: repeat(2, 1fr); }
}

.socials { display: flex; gap: 4px; margin-top: 5px; flex-wrap: wrap; }
.socialPill {
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 2px 6px;
  border-radius: 3px;
  background: rgba(255,255,255,0.06);
  border: 1px solid rgba(255,255,255,0.14);
  color: rgba(255,255,255,0.7);
  text-decoration: none;
  transition: all 0.12s;
}
.socialPill:hover { border-color: var(--coral); color: #fff; }

'@
Write-FileSafe 'src/components/dashboard.module.css' $content

# ---- src/lib/csv.ts ----
$content = @'
import type { ScoredLead } from "./scoring";

interface ExportLead extends ScoredLead {
  phoneFormatted?: string | null;
  phoneType?: string | null;
  phoneValid?: boolean | null;
  enrichedEmails?: string[];
  enrichedPhones?: string[];
  socials?: Record<string, string>;
}

const COLUMNS: Array<{ header: string; get: (l: ExportLead) => string }> = [
  { header: "Name", get: (l) => l.name },
  { header: "Category", get: (l) => String(l.category ?? "") },
  { header: "Tier", get: (l) => l.tier },
  { header: "Score", get: (l) => String(l.score) },
  { header: "Phone", get: (l) => l.phoneFormatted ?? l.phone ?? "" },
  { header: "Phone Type", get: (l) => l.phoneType ?? "" },
  { header: "Phone Valid", get: (l) => (l.phoneValid == null ? "" : l.phoneValid ? "yes" : "no") },
  { header: "Website", get: (l) => l.website ?? "" },
  { header: "Email", get: (l) => l.email ?? "" },
  { header: "Enriched Emails", get: (l) => (l.enrichedEmails ?? []).join("; ") },
  { header: "Enriched Phones", get: (l) => (l.enrichedPhones ?? []).join("; ") },
  { header: "Facebook", get: (l) => l.socials?.facebook ?? "" },
  { header: "Instagram", get: (l) => l.socials?.instagram ?? "" },
  { header: "LinkedIn", get: (l) => l.socials?.linkedin ?? "" },
  { header: "Address", get: (l) => l.address ?? "" },
  { header: "City", get: (l) => l.city ?? "" },
  { header: "State", get: (l) => l.state ?? "" },
  { header: "Rating", get: (l) => (l.rating == null ? "" : String(l.rating)) },
  { header: "Reviews", get: (l) => (l.reviewCount == null ? "" : String(l.reviewCount)) },
];

function escapeCell(value: string): string {
  if (/[",\n]/.test(value)) {
    return '"' + value.replace(/"/g, '""') + '"';
  }
  return value;
}

export function leadsToCsv(leads: ExportLead[]): string {
  const head = COLUMNS.map((c) => c.header).join(",");
  const rows = leads.map((l) =>
    COLUMNS.map((c) => escapeCell(c.get(l))).join(",")
  );
  return [head, ...rows].join("\n");
}

export function downloadCsv(leads: ExportLead[], filename = "leads.csv") {
  const csv = leadsToCsv(leads);
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

'@
Write-FileSafe 'src/lib/csv.ts' $content

Write-Host ''
Write-Host 'Done. 6 files updated (.bak backups saved alongside each).' -ForegroundColor Cyan
Write-Host 'No new dependencies — just restart the dev server:' -ForegroundColor Cyan
Write-Host '  npm run dev' -ForegroundColor White
