# ============================================================
# LeadFinder updater v5 - adds Persistence (solo mode, no auth).
#
# BEFORE running this, you also need to:
#   1. Create a fresh Supabase project
#   2. Run supabase/schema.sql in its SQL editor
#   3. Create .env.local with your project URL + anon key (see below)
#
# Run from inside your leadfinder folder:
#   cd C:\Users\user\Documents\leadfinder
#   powershell -ExecutionPolicy Bypass -File .\update-leadfinder-v5.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

if (-not (Test-Path 'package.json') -or -not (Test-Path 'src')) {
  Write-Host 'ERROR: Run this from inside the leadfinder folder.' -ForegroundColor Red
  exit 1
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-FileSafe($path, $content) {
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if ((Test-Path $path) -and -not (Test-Path "$path.bak")) { Copy-Item $path "$path.bak" }
  $full = Join-Path (Get-Location) $path
  [System.IO.File]::WriteAllText($full, $content, $utf8NoBom)
  Write-Host "  updated $path" -ForegroundColor Green
}

# ---- src/lib/supabase.ts ----
$content = @'
import { createBrowserClient } from "@supabase/ssr";

/**
 * Supabase client (browser). Optional — the tool runs without it.
 * Only saved searches + lead persistence need this. If the env vars
 * aren't set, `isSupabaseConfigured()` returns false and the UI hides
 * the save/load features.
 */

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

export function isSupabaseConfigured(): boolean {
  return Boolean(url && anonKey);
}

export function createClient() {
  if (!url || !anonKey) {
    throw new Error(
      "Supabase isn't configured. Add NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY."
    );
  }
  return createBrowserClient(url, anonKey);
}

'@
Write-FileSafe 'src/lib/supabase.ts' $content

# ---- src/lib/persistence.ts ----
$content = @'
import { createClient, isSupabaseConfigured } from "./supabase";
import type { ScoredLead } from "./scoring";

/**
 * Persistence — SOLO mode (no auth). Saves to one shared bucket.
 * All functions no-op gracefully if Supabase isn't configured, so the rest
 * of the app never has to check first.
 */

interface SaveableLead extends ScoredLead {
  phoneFormatted?: string | null;
  phoneType?: string | null;
  phoneValid?: boolean | null;
  enrichedEmails?: string[];
  enrichedPhones?: string[];
  socials?: Record<string, string>;
}

export interface SaveResult {
  saved: number;
  searchId: string | null;
}

/**
 * Save a search and its leads. Leads dedupe on source_id (a unique column),
 * so re-running a search refreshes existing rows rather than duplicating.
 */
export async function saveSearch(
  params: { mode: string; location: string; categories: string[]; radiusMiles: number },
  leads: SaveableLead[]
): Promise<SaveResult> {
  if (!isSupabaseConfigured()) return { saved: 0, searchId: null };

  const supabase = createClient();

  const { data: searchRow, error: searchErr } = await supabase
    .from("lf_searches")
    .insert({
      mode: params.mode,
      location: params.location,
      categories: params.categories,
      radius_miles: params.radiusMiles,
      result_count: leads.length,
    })
    .select("id")
    .single();

  if (searchErr || !searchRow) return { saved: 0, searchId: null };
  const searchId = searchRow.id;

  const rows = leads.map((l) => ({
    search_id: searchId,
    source_id: l.sourceId,
    source: l.source,
    name: l.name,
    category: String(l.category ?? ""),
    phone: l.phoneFormatted ?? l.phone ?? null,
    phone_type: l.phoneType ?? null,
    phone_valid: l.phoneValid ?? null,
    website: l.website ?? null,
    email: l.email ?? l.enrichedEmails?.[0] ?? null,
    address: l.address ?? null,
    city: l.city ?? null,
    state: l.state ?? null,
    postal_code: l.postalCode ?? null,
    lat: l.lat ?? null,
    lng: l.lng ?? null,
    rating: l.rating ?? null,
    review_count: l.reviewCount ?? null,
    score: l.score,
    tier: l.tier,
    enriched: Boolean(l.enrichedEmails || l.enrichedPhones),
    enriched_emails: l.enrichedEmails ?? null,
    enriched_phones: l.enrichedPhones ?? null,
    socials: l.socials ?? null,
  }));

  // Upsert on source_id so the saved DB stays deduped across every search
  const { error: leadsErr } = await supabase
    .from("lf_leads")
    .upsert(rows, { onConflict: "source_id", ignoreDuplicates: false });

  if (leadsErr) return { saved: 0, searchId };
  return { saved: rows.length, searchId };
}

export interface SavedLead {
  source_id: string;
  name: string;
  category: string | null;
  phone: string | null;
  phone_type: string | null;
  website: string | null;
  email: string | null;
  city: string | null;
  state: string | null;
  tier: string;
  score: number;
  status: string;
  notes: string | null;
  enriched_emails: string[] | null;
  enriched_phones: string[] | null;
  socials: Record<string, string> | null;
}

/** Load the full saved lead database (most valuable first). */
export async function loadSavedLeads(): Promise<SavedLead[]> {
  if (!isSupabaseConfigured()) return [];
  const supabase = createClient();
  const { data } = await supabase
    .from("lf_leads")
    .select(
      "source_id,name,category,phone,phone_type,website,email,city,state,tier,score,status,notes,enriched_emails,enriched_phones,socials"
    )
    .order("score", { ascending: false })
    .limit(5000);
  return (data as SavedLead[]) ?? [];
}

export async function updateLeadStatus(sourceId: string, status: string): Promise<boolean> {
  if (!isSupabaseConfigured()) return false;
  const supabase = createClient();
  const { error } = await supabase
    .from("lf_leads")
    .update({ status })
    .eq("source_id", sourceId);
  return !error;
}

export async function updateLeadNotes(sourceId: string, notes: string): Promise<boolean> {
  if (!isSupabaseConfigured()) return false;
  const supabase = createClient();
  const { error } = await supabase
    .from("lf_leads")
    .update({ notes })
    .eq("source_id", sourceId);
  return !error;
}

export interface DbStats {
  totalLeads: number;
  byStatus: Record<string, number>;
}

export async function getDbStats(): Promise<DbStats> {
  if (!isSupabaseConfigured()) return { totalLeads: 0, byStatus: {} };
  const supabase = createClient();
  const { data, count } = await supabase
    .from("lf_leads")
    .select("status", { count: "exact" });
  const byStatus: Record<string, number> = {};
  for (const row of (data as { status: string }[]) ?? []) {
    byStatus[row.status] = (byStatus[row.status] ?? 0) + 1;
  }
  return { totalLeads: count ?? 0, byStatus };
}

'@
Write-FileSafe 'src/lib/persistence.ts' $content

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
  const [cityList, setCityList] = useState<string[]>([]);
  const [cityInput, setCityInput] = useState("");
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

  function addCities(raw: string) {
    const parts = raw
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    if (parts.length === 0) return;
    setCityList((prev) => {
      const set = new Set(prev.map((c) => c.toLowerCase()));
      const next = [...prev];
      for (const p of parts) {
        if (!set.has(p.toLowerCase())) next.push(p);
      }
      return next;
    });
    setCityInput("");
  }

  function removeCity(city: string) {
    setCityList((prev) => prev.filter((c) => c !== city));
  }

  async function runMultiSweep() {
    if (selected.size === 0) { setError("Pick at least one category."); return; }
    if (cityList.length === 0) { setError("Add at least one city to sweep."); return; }
    setError("");
    setLoading(true);
    setLeads([]);
    try {
      const res = await fetch("/api/multi-sweep", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          categories: [...selected],
          cities: cityList,
          radiusMiles: radius,
        }),
      });
      const data = await res.json();
      if (!res.ok) { setError(data.error ?? "Multi-city sweep failed."); setLoading(false); return; }
      setLeads(data.leads);
      setResolvedLocation(data.location ?? "Multi-city sweep");
      if (data.citiesFailed?.length) {
        setError(`Couldn't resolve: ${data.citiesFailed.join(", ")}`);
      }
    } catch {
      setError("Something went wrong running the multi-city sweep.");
    }
    setLoading(false);
  }

  async function runNationalSweep() {
    if (selected.size === 0) { setError("Pick at least one category."); return; }
    setError("");
    setLoading(true);
    setLeads([]);
    try {
      const res = await fetch("/api/sweep", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          categories: [...selected],
          radiusMiles: radius,
        }),
      });
      const data = await res.json();
      if (!res.ok) { setError(data.error ?? "Sweep failed."); setLoading(false); return; }
      setLeads(data.leads);
      setResolvedLocation(data.location ?? "National sweep");
    } catch {
      setError("Something went wrong running the national sweep.");
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
    setSaveMsg("Saving...");
    try {
      const result = await saveSearch(
        {
          mode: "search",
          location: resolvedLocation || location,
          categories: [...selected],
          radiusMiles: radius,
        },
        leads as never
      );
      if (result.saved > 0) {
        setSaveMsg(`Saved ${result.saved} to database`);
      } else {
        setSaveMsg("Save failed - check Supabase config");
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
      {/* Sidebar - search controls */}
      <aside className={styles.sidebar}>
        <div className={styles.brand}>
          <span className={styles.brandMark}>&#9670;</span>
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
          <label className={styles.label}>Or sweep multiple cities</label>
          <input
            className={styles.input}
            placeholder="Type a city, press Enter"
            value={cityInput}
            onChange={(e) => setCityInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") { e.preventDefault(); addCities(cityInput); }
            }}
          />
          {cityList.length > 0 && (
            <div className={styles.cityChips}>
              {cityList.map((c) => (
                <span key={c} className={styles.cityChip}>
                  {c}
                  <button className={styles.cityChipX} onClick={() => removeCity(c)} aria-label={`Remove ${c}`}>
                    &times;
                  </button>
                </span>
              ))}
            </div>
          )}
        </div>

        <div className={styles.field}>
          <label className={styles.label}>Radius - {radius} mi</label>
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
          {loading ? "Searching..." : "Find leads"}
        </button>

        {cityList.length > 0 && (
          <button className={styles.sweepBtn} onClick={runMultiSweep} disabled={loading}>
            {loading ? "Sweeping..." : `Sweep my ${cityList.length} cities`}
          </button>
        )}

        <button className={styles.sweepBtn} onClick={runNationalSweep} disabled={loading}>
          {loading ? "Sweeping..." : "National sweep (all metros)"}
        </button>

        <p className={styles.sourceNote}>
          Source: OpenStreetMap (free). Drop in a Google Places key to upgrade
          to ratings and fuller phone coverage - no other changes needed.
        </p>
      </aside>

      {/* Main - results */}
      <main className={styles.main}>
        {leads.length === 0 && !loading && (
          <div className={styles.empty}>
            <div className={styles.emptyMark}>&#9670;</div>
            <h2>Start with a trade and a place</h2>
            <p>
              Pick one or more trades, enter a city or ZIP, and pull a ranked
              list of businesses. The ones with a website rise to the top -
              they're the most reachable.
            </p>
          </div>
        )}

        {(leads.length > 0 || loading) && (
          <>
            <header className={styles.resultsHead}>
              <div>
                <h1 className={styles.resultsTitle}>
                  {loading ? "Searching..." : `${stats.total} leads`}
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
                placeholder="Filter by name or city..."
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
                            {l.rating != null && ` &middot; &#9733; ${l.rating}`}
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
                            <span className={styles.dim}>-</span>
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
                            <span className={styles.dim}>-</span>
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
                            <span className={styles.dim}>-</span>
                          )}
                        </td>
                        <td>
                          {l.website && (
                            <button
                              className={styles.enrichBtn}
                              onClick={() => enrichOne(l.sourceId)}
                              disabled={l.enriching}
                            >
                              {l.enriching ? "..." : l.enrichedEmails ? "Re-run" : "Enrich"}
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

# ---- supabase/schema.sql ----
$content = @'
-- ============================================================
-- LeadFinder — Solo schema (no auth, single-user)
-- Run this in your fresh Supabase project's SQL editor.
--
-- NOTE: This is the SOLO version — no per-user security. Anyone who can
-- reach the database can read/write it. Fine for local/personal use. If you
-- ever deploy this publicly, add authentication first.
-- ============================================================

create table if not exists lf_searches (
  id            uuid primary key default gen_random_uuid(),
  mode          text not null,
  location      text not null,
  categories    text[] not null,
  radius_miles  int not null default 25,
  result_count  int not null default 0,
  created_at    timestamptz not null default now()
);

create table if not exists lf_leads (
  id             uuid primary key default gen_random_uuid(),
  search_id      uuid references lf_searches(id) on delete set null,

  source_id      text not null unique,
  source         text not null,

  name           text not null,
  category       text,
  phone          text,
  phone_type     text,
  phone_valid    boolean,
  website        text,
  email          text,
  address        text,
  city           text,
  state          text,
  postal_code    text,
  lat            double precision,
  lng            double precision,
  rating         numeric,
  review_count   int,

  score          int not null default 0,
  tier           text not null default 'thin',

  enriched         boolean not null default false,
  enriched_emails  text[],
  enriched_phones  text[],
  socials          jsonb,

  status         text not null default 'new',
  notes          text,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists lf_leads_tier_idx   on lf_leads(tier);
create index if not exists lf_leads_status_idx on lf_leads(status);
create index if not exists lf_leads_city_idx   on lf_leads(city);

create or replace function lf_touch_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists lf_leads_touch on lf_leads;
create trigger lf_leads_touch
  before update on lf_leads
  for each row execute function lf_touch_updated_at();

alter table lf_searches enable row level security;
alter table lf_leads    enable row level security;

drop policy if exists "anon full access searches" on lf_searches;
create policy "anon full access searches" on lf_searches
  for all using (true) with check (true);

drop policy if exists "anon full access leads" on lf_leads;
create policy "anon full access leads" on lf_leads
  for all using (true) with check (true);

'@
Write-FileSafe 'supabase/schema.sql' $content

Write-Host ''
Write-Host 'Files updated. Persistence (solo) is wired in.' -ForegroundColor Cyan
Write-Host 'Make sure you have created .env.local with your Supabase URL + anon key,' -ForegroundColor Yellow
Write-Host 'and run supabase/schema.sql in your Supabase SQL editor.' -ForegroundColor Yellow
Write-Host 'Then: npm run dev' -ForegroundColor White
