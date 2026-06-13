# LeadFinder — Home Services Lead Extraction

A standalone Next.js tool that pulls ranked home-service business leads
(handyman, GC, HVAC, plumber, electrician, and more), prioritizing businesses
with a website — the strongest free signal that a business is real, active, and
reachable — then enriches those websites for the freshest contact info.

## What it does

- **Search** by trade + location + radius
- **Free data** from OpenStreetMap (no API key, no card)
- **Website-first scoring** — businesses with a site rank to the top, tiered
  Gold (website + phone) → Website → Phone-only → No contact
- **Free phone validation** — format/type/region via libphonenumber (flags
  malformed numbers; does not confirm a live connection)
- **Website enrichment** — visits each business site + its contact page and
  extracts emails and phone numbers
- **Filters** — has website, has phone, name/city search
- **CSV export** of the current (filtered) list
- **Supabase persistence** (optional) — saved searches, deduped lead table,
  pipeline status (new / contacted / qualified / won / dead)

## Stack

Next.js (App Router) · TypeScript · Supabase · libphonenumber-js
Free data: OpenStreetMap Overpass + Nominatim geocoding

## Setup

1. Install dependencies:
   ```bash
   npm install
   npm install libphonenumber-js
   ```

2. (Optional, for saved lists) Create the Supabase tables — run
   `supabase/schema.sql` in your Supabase SQL editor, then add to `.env.local`:
   ```
   NEXT_PUBLIC_SUPABASE_URL=...
   NEXT_PUBLIC_SUPABASE_ANON_KEY=...
   ```
   The search + export + enrichment all work without Supabase; persistence is
   the only feature that needs it.

3. Run it:
   ```bash
   npm run dev
   ```

## The paid upgrade path (plug and play)

The whole data layer is behind a provider interface (`src/lib/providers`). The
free OpenStreetMap provider and a fully-written Google Places provider both
implement the same contract. To upgrade:

1. Get a Google Places API key (Google Cloud → Places API New).
2. Add to `.env.local`:
   ```
   GOOGLE_PLACES_API_KEY=your_key
   ```
3. That's it. The Google provider reports itself as "configured" and can be
   selected. To make it the default, change `DEFAULT_PROVIDER_KEY` in
   `src/lib/providers/index.ts` to `"google_places"`.

No dashboard, scoring, enrichment, or export code changes — they all code
against the provider interface, not a specific source.

### Adding another provider (Outscraper, SerpAPI, etc.)

1. Create `src/lib/providers/yourprovider.ts` implementing `LeadProvider`.
2. `register(new YourProvider())` in `src/lib/providers/index.ts`.
3. Done — it appears everywhere automatically.

## Live-connection phone checking (paid, optional)

The free validation checks number *structure*. To confirm a line is actually
connected, add a Twilio Lookup (or NumVerify) call as a second validation pass —
same plug-in pattern. You already use Twilio, so Twilio Lookup is the natural
fit.

## Honest limitations of the free tier

- OpenStreetMap coverage of small US home-service businesses is patchy; phone
  fill rate is lower than paid sources. The website-first ranking is the
  deliberate workaround.
- Overpass/Nominatim are shared free services with rate limits — fine for
  experimentation, not high-volume production.
- Website enrichment depends on each site being reachable and exposing contact
  info in HTML (not behind JS-only rendering or images).
