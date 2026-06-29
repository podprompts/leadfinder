"use client";

import { useState, useEffect, useMemo, useCallback } from "react";
import Link from "next/link";
import {
  loadSavedLeads,
  updateLeadStatus,
  updateLeadNotes,
  type SavedLead,
} from "@/lib/persistence";
import { isSupabaseConfigured } from "@/lib/supabase";
import styles from "./savedleads.module.css";

const STATUSES = ["new", "contacted", "qualified", "won", "dead"] as const;
type Status = (typeof STATUSES)[number];

const STATUS_LABEL: Record<string, string> = {
  new: "New",
  contacted: "Contacted",
  qualified: "Qualified",
  won: "Won",
  dead: "Dead",
};

export default function SavedLeads() {
  const [leads, setLeads] = useState<SavedLead[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [search, setSearch] = useState("");
  const [notesDraft, setNotesDraft] = useState<Record<string, string>>({});
  const [page, setPage] = useState(1);
  const [jumpVal, setJumpVal] = useState("");
  const PAGE_SIZE = 20;
  const configured = isSupabaseConfigured();

  const load = useCallback(async () => {
    setLoading(true);
    const data = await loadSavedLeads();
    setLeads(data);
    setLoading(false);
  }, []);

  useEffect(() => {
    if (configured) load();
    else setLoading(false);
  }, [configured, load]);

  async function changeStatus(sourceId: string, status: Status) {
    // optimistic update
    setLeads((prev) =>
      prev.map((l) => (l.source_id === sourceId ? { ...l, status } : l))
    );
    await updateLeadStatus(sourceId, status);
  }

  async function saveNotes(sourceId: string) {
    const notes = notesDraft[sourceId];
    if (notes === undefined) return;
    setLeads((prev) =>
      prev.map((l) => (l.source_id === sourceId ? { ...l, notes } : l))
    );
    await updateLeadNotes(sourceId, notes);
  }

  useEffect(() => { setPage(1); }, [statusFilter, search]);

  const filtered = useMemo(() => {
    return leads.filter((l) => {
      if (statusFilter !== "all" && l.status !== statusFilter) return false;
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
  }, [leads, statusFilter, search]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const counts = useMemo(() => {
    const c: Record<string, number> = { all: leads.length };
    for (const s of STATUSES) c[s] = 0;
    for (const l of leads) c[l.status] = (c[l.status] ?? 0) + 1;
    return c;
  }, [leads]);

  if (!configured) {
    return (
      <div className={styles.shell}>
        <div className={styles.notConfigured}>
          <h2>Database not connected</h2>
          <p>
            Add your Supabase URL and key to <code>.env.local</code> and restart
            the dev server to use saved leads.
          </p>
          <Link href="/" className={styles.backLink}>&larr; Back to search</Link>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.shell}>
      <header className={styles.head}>
        <div>
          <Link href="/" className={styles.backLink}>&larr; Search</Link>
          <h1 className={styles.title}>Saved leads</h1>
          <p className={styles.sub}>
            {loading ? "Loading..." : `${leads.length} leads in your database`}
          </p>
        </div>
        <button className={styles.refreshBtn} onClick={load} disabled={loading}>
          Refresh
        </button>
      </header>

      {/* Status filter pills */}
      <div className={styles.statusBar}>
        {(["all", ...STATUSES] as string[]).map((s) => (
          <button
            key={s}
            className={`${styles.statusPill} ${statusFilter === s ? styles.statusPillOn : ""}`}
            onClick={() => setStatusFilter(s)}
          >
            {s === "all" ? "All" : STATUS_LABEL[s]} <span className={styles.count}>{counts[s] ?? 0}</span>
          </button>
        ))}
      </div>

      <input
        className={styles.searchInput}
        placeholder="Filter by name or city..."
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />

      {!loading && leads.length === 0 && (
        <div className={styles.empty}>
          <p>No saved leads yet. Run a search and click &ldquo;Save to database.&rdquo;</p>
          <Link href="/" className={styles.backLink}>&larr; Go search</Link>
        </div>
      )}

      {filtered.length > 0 && (
        <div className={styles.tableWrap}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th>Business</th>
                <th>Phone</th>
                <th>Website</th>
                <th>Email</th>
                <th>Status</th>
                <th>Notes</th>
              </tr>
            </thead>
            <tbody>
              {paginated.map((l) => (
                <tr key={l.source_id} className={styles[`row_${l.status}`] ?? ""}>
                  <td>
                    <div className={styles.bizName}>{l.name}</div>
                    <div className={styles.bizMeta}>
                      {[l.city, l.state].filter(Boolean).join(", ")}
                      {l.category ? ` - ${l.category}` : ""}
                    </div>
                  </td>
                  <td>
                    {l.phone ? <span>{l.phone}</span> : <span className={styles.dim}>-</span>}
                    {l.enriched_phones?.length ? (
                      <div className={styles.extra}>
                        {l.enriched_phones.map((p) => <div key={p}>{p}</div>)}
                      </div>
                    ) : null}
                  </td>
                  <td>
                    {l.website ? (
                      <a href={l.website} target="_blank" rel="noopener noreferrer" className={styles.link}>
                        {prettyHost(l.website)}
                      </a>
                    ) : (
                      <span className={styles.dim}>-</span>
                    )}
                  </td>
                  <td>
                    {l.email || l.enriched_emails?.[0] ? (
                      <a href={`mailto:${l.email ?? l.enriched_emails?.[0]}`} className={styles.link}>
                        {l.email ?? l.enriched_emails?.[0]}
                      </a>
                    ) : (
                      <span className={styles.dim}>-</span>
                    )}
                  </td>
                  <td>
                    <select
                      className={styles.statusSelect}
                      value={l.status}
                      onChange={(e) => changeStatus(l.source_id, e.target.value as Status)}
                    >
                      {STATUSES.map((s) => (
                        <option key={s} value={s}>{STATUS_LABEL[s]}</option>
                      ))}
                    </select>
                  </td>
                  <td>
                    <input
                      className={styles.notesInput}
                      defaultValue={l.notes ?? ""}
                      placeholder="Add note..."
                      onChange={(e) =>
                        setNotesDraft((prev) => ({ ...prev, [l.source_id]: e.target.value }))
                      }
                      onBlur={() => saveNotes(l.source_id)}
                      onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {totalPages > 1 && (
        <div style={{ display: "flex", alignItems: "center", gap: "0.75rem", marginTop: "1.5rem", justifyContent: "center", flexWrap: "wrap" }}>
          <button
            onClick={() => setPage(p => Math.max(1, p - 1))}
            disabled={page === 1}
            style={{ padding: "6px 14px", background: page === 1 ? "#2a2a2a" : "#e8521a", color: "#fff", border: "none", borderRadius: "6px", cursor: page === 1 ? "not-allowed" : "pointer", opacity: page === 1 ? 0.4 : 1 }}
          >&#8592;</button>
          <span style={{ color: "#aaa", fontSize: "13px" }}>Page {page} of {totalPages} &middot; {filtered.length} leads</span>
          <button
            onClick={() => setPage(p => Math.min(totalPages, p + 1))}
            disabled={page === totalPages}
            style={{ padding: "6px 14px", background: page === totalPages ? "#2a2a2a" : "#e8521a", color: "#fff", border: "none", borderRadius: "6px", cursor: page === totalPages ? "not-allowed" : "pointer", opacity: page === totalPages ? 0.4 : 1 }}
          >&#8594;</button>
          <input
            type="number"
            min={1}
            max={totalPages}
            value={jumpVal}
            onChange={e => setJumpVal(e.target.value)}
            onKeyDown={e => {
              if (e.key === "Enter") {
                const n = parseInt(jumpVal);
                if (!isNaN(n) && n >= 1 && n <= totalPages) { setPage(n); setJumpVal(""); }
              }
            }}
            placeholder="Go to page"
            style={{ width: "90px", padding: "6px 10px", background: "#1a1a1a", border: "1px solid #444", borderRadius: "6px", color: "#fff", fontSize: "13px" }}
          />
        </div>
      
      )}
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
