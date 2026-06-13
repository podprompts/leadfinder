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
