import type { RawLead } from "./providers/types";

/**
 * Lead scoring.
 *
 * The core thesis of this tool: in free (and even paid) business data, the
 * presence of a website is the strongest free signal that a business is real,
 * active, and reachable — and the website itself is the best path to a current
 * phone/email. So we rank website-having businesses to the top, with phone as
 * the secondary signal.
 *
 * Tiers (highest to lowest):
 *   GOLD     — has website AND phone
 *   WEBSITE  — has website, no phone (still high value: enrich the site)
 *   PHONE    — has phone, no website
 *   THIN     — neither (lowest value, kept but sorted last)
 */

export type LeadTier = "gold" | "website" | "phone" | "thin";

export interface ScoredLead extends RawLead {
  score: number;
  tier: LeadTier;
}

export function scoreLead(lead: RawLead): { score: number; tier: LeadTier } {
  const hasWebsite = Boolean(lead.website && lead.website.trim());
  const hasPhone = Boolean(lead.phone && lead.phone.trim());
  const hasEmail = Boolean(lead.email && lead.email.trim());

  let score = 0;
  let tier: LeadTier;

  // Website is weighted heaviest — it's the liveness + reachability signal
  if (hasWebsite) score += 50;
  if (hasPhone) score += 30;
  if (hasEmail) score += 10;

  // Completeness bonuses
  if (lead.address) score += 4;
  if (lead.city) score += 2;
  if (lead.rating != null) score += Math.round((lead.rating / 5) * 4); // up to +4

  // Tiering
  if (hasWebsite && hasPhone) tier = "gold";
  else if (hasWebsite) tier = "website";
  else if (hasPhone) tier = "phone";
  else tier = "thin";

  return { score, tier };
}

export function scoreAndSort(leads: RawLead[]): ScoredLead[] {
  return leads
    .map((l) => {
      const { score, tier } = scoreLead(l);
      return { ...l, score, tier };
    })
    .sort((a, b) => b.score - a.score);
}

export const TIER_LABEL: Record<LeadTier, string> = {
  gold: "Website + Phone",
  website: "Website",
  phone: "Phone only",
  thin: "No contact",
};
