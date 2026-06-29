import { createClient, isSupabaseConfigured } from "./supabase";
import type { ScoredLead } from "./scoring";

/**
 * Persistence â€” SOLO mode (no auth). Saves to one shared bucket.
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

  if (searchErr || !searchRow) { console.error("[persistence] lf_searches insert error:", JSON.stringify(searchErr)); return { saved: 0, searchId: null }; }
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

  if (leadsErr) { console.error("[persistence] lf_leads upsert error:", JSON.stringify(leadsErr)); return { saved: 0, searchId }; }
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
