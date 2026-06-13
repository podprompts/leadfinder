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
