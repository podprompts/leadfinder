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
