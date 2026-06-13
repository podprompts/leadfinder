# ============================================================
# LeadFinder updater v4 - adds Multi-City Sweep.
# Run from inside your leadfinder folder:
#   cd C:\Users\user\Documents\leadfinder
#   powershell -ExecutionPolicy Bypass -File .\update-leadfinder-v4.ps1
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

.sweepBtn {
  margin-top: 0.5rem;
  padding: 11px;
  background: transparent;
  color: rgba(255,255,255,0.7);
  border: 1px solid rgba(255,255,255,0.18);
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  cursor: pointer;
  transition: all 0.12s;
}
.sweepBtn:hover:not(:disabled) { border-color: var(--coral); color: #fff; }
.sweepBtn:disabled { opacity: 0.5; cursor: default; }

.cityChips { display: flex; flex-wrap: wrap; gap: 5px; margin-top: 8px; }
.cityChip {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  padding: 4px 8px;
  border-radius: 4px;
  background: rgba(232,82,26,0.12);
  border: 1px solid var(--coral-border);
  color: #fff;
}
.cityChipX {
  background: none;
  border: none;
  color: rgba(255,255,255,0.6);
  cursor: pointer;
  font-size: 14px;
  line-height: 1;
  padding: 0;
}
.cityChipX:hover { color: var(--coral-light); }

'@
Write-FileSafe 'src/components/dashboard.module.css' $content

# ---- src/app/api/multi-sweep/route.ts ----
$content = @'
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

'@
Write-FileSafe 'src/app/api/multi-sweep/route.ts' $content

Write-Host ''
Write-Host 'Done. Multi-City Sweep added.' -ForegroundColor Cyan
Write-Host 'Stop the dev server (Ctrl+C) if running, then: npm run dev' -ForegroundColor White
