# ============================================================
# LeadFinder updater v3 - adds National Sweep + fixes Enrich button.
# Run from inside your leadfinder folder:
#   cd C:\Users\user\Documents\leadfinder
#   powershell -ExecutionPolicy Bypass -File .\update-leadfinder-v3.ps1
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

'@
Write-FileSafe 'src/components/dashboard.module.css' $content

# ---- src/lib/metros.ts ----
$content = @'
/**
 * Major US metros for "National Sweep" mode.
 *
 * The free OpenStreetMap/Overpass servers can't handle one nationwide query —
 * it times out. So national coverage works by running the search across these
 * metro centers in sequence and merging the results. This list covers the
 * largest population centers; coordinates are metro centroids.
 *
 * ~50 metros balances coverage against runtime (each is one Overpass call).
 */

export interface Metro {
  name: string;
  lat: number;
  lng: number;
}

export const US_METROS: Metro[] = [
  { name: "New York, NY", lat: 40.7128, lng: -74.006 },
  { name: "Los Angeles, CA", lat: 34.0522, lng: -118.2437 },
  { name: "Chicago, IL", lat: 41.8781, lng: -87.6298 },
  { name: "Houston, TX", lat: 29.7604, lng: -95.3698 },
  { name: "Phoenix, AZ", lat: 33.4484, lng: -112.074 },
  { name: "Philadelphia, PA", lat: 39.9526, lng: -75.1652 },
  { name: "San Antonio, TX", lat: 29.4241, lng: -98.4936 },
  { name: "San Diego, CA", lat: 32.7157, lng: -117.1611 },
  { name: "Dallas, TX", lat: 32.7767, lng: -96.797 },
  { name: "Austin, TX", lat: 30.2672, lng: -97.7431 },
  { name: "San Jose, CA", lat: 37.3382, lng: -121.8863 },
  { name: "Jacksonville, FL", lat: 30.3322, lng: -81.6557 },
  { name: "Fort Worth, TX", lat: 32.7555, lng: -97.3308 },
  { name: "Columbus, OH", lat: 39.9612, lng: -82.9988 },
  { name: "Charlotte, NC", lat: 35.2271, lng: -80.8431 },
  { name: "Indianapolis, IN", lat: 39.7684, lng: -86.1581 },
  { name: "San Francisco, CA", lat: 37.7749, lng: -122.4194 },
  { name: "Seattle, WA", lat: 47.6062, lng: -122.3321 },
  { name: "Denver, CO", lat: 39.7392, lng: -104.9903 },
  { name: "Washington, DC", lat: 38.9072, lng: -77.0369 },
  { name: "Boston, MA", lat: 42.3601, lng: -71.0589 },
  { name: "Nashville, TN", lat: 36.1627, lng: -86.7816 },
  { name: "Oklahoma City, OK", lat: 35.4676, lng: -97.5164 },
  { name: "Las Vegas, NV", lat: 36.1699, lng: -115.1398 },
  { name: "Portland, OR", lat: 45.5152, lng: -122.6784 },
  { name: "Memphis, TN", lat: 35.1495, lng: -90.049 },
  { name: "Louisville, KY", lat: 38.2527, lng: -85.7585 },
  { name: "Baltimore, MD", lat: 39.2904, lng: -76.6122 },
  { name: "Milwaukee, WI", lat: 43.0389, lng: -87.9065 },
  { name: "Albuquerque, NM", lat: 35.0844, lng: -106.6504 },
  { name: "Tucson, AZ", lat: 32.2226, lng: -110.9747 },
  { name: "Fresno, CA", lat: 36.7378, lng: -119.7871 },
  { name: "Sacramento, CA", lat: 38.5816, lng: -121.4944 },
  { name: "Kansas City, MO", lat: 39.0997, lng: -94.5786 },
  { name: "Atlanta, GA", lat: 33.749, lng: -84.388 },
  { name: "Miami, FL", lat: 25.7617, lng: -80.1918 },
  { name: "Raleigh, NC", lat: 35.7796, lng: -78.6382 },
  { name: "Omaha, NE", lat: 41.2565, lng: -95.9345 },
  { name: "Minneapolis, MN", lat: 44.9778, lng: -93.265 },
  { name: "Tampa, FL", lat: 27.9506, lng: -82.4572 },
  { name: "New Orleans, LA", lat: 29.9511, lng: -90.0715 },
  { name: "Cleveland, OH", lat: 41.4993, lng: -81.6944 },
  { name: "St. Louis, MO", lat: 38.627, lng: -90.1994 },
  { name: "Pittsburgh, PA", lat: 40.4406, lng: -79.9959 },
  { name: "Cincinnati, OH", lat: 39.1031, lng: -84.512 },
  { name: "Orlando, FL", lat: 28.5383, lng: -81.3792 },
  { name: "Salt Lake City, UT", lat: 40.7608, lng: -111.891 },
  { name: "Detroit, MI", lat: 42.3314, lng: -83.0458 },
  { name: "Richmond, VA", lat: 37.5407, lng: -77.436 },
  { name: "Birmingham, AL", lat: 33.5186, lng: -86.8104 },
];

'@
Write-FileSafe 'src/lib/metros.ts' $content

# ---- src/app/api/sweep/route.ts ----
$content = @'
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

'@
Write-FileSafe 'src/app/api/sweep/route.ts' $content

Write-Host ''
Write-Host 'Done. National Sweep added + Enrich button fixed.' -ForegroundColor Cyan
Write-Host 'Stop the dev server (Ctrl+C) if running, then: npm run dev' -ForegroundColor White
