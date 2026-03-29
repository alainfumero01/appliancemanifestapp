create or replace function public.normalize_model_number(input text)
returns text
language sql
immutable
as $$
  select regexp_replace(upper(coalesce(input, '')), '[^A-Z0-9]', '', 'g')
$$;

create table if not exists public.product_lookup_candidates (
  normalized_model_number text primary key,
  product_name text not null,
  msrp numeric(10,2) not null check (msrp >= 0),
  source text not null,
  confidence double precision not null default 0,
  verification_state text not null default 'provisional'
    check (verification_state in ('provisional', 'promoted', 'confirmed', 'rejected')),
  hit_count integer not null default 1 check (hit_count >= 0),
  first_seen_at timestamptz not null default timezone('utc', now()),
  last_seen_at timestamptz not null default timezone('utc', now()),
  last_used_at timestamptz not null default timezone('utc', now()),
  last_promoted_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.model_aliases (
  alias_model_number text primary key,
  canonical_model_number text not null,
  source text not null default 'operator-correction',
  confidence double precision not null default 1,
  hit_count integer not null default 0 check (hit_count >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  last_seen_at timestamptz not null default timezone('utc', now()),
  check (alias_model_number <> canonical_model_number)
);

create table if not exists public.product_lookup_logs (
  id uuid primary key default gen_random_uuid(),
  query_model_number text not null,
  normalized_query_model_number text not null,
  resolved_model_number text not null,
  lookup_layer text not null
    check (lookup_layer in ('catalog', 'alias_catalog', 'candidate', 'alias_candidate', 'ai', 'not_appliance')),
  response_status text not null,
  resolved_source text,
  confidence double precision,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists model_aliases_canonical_model_number_idx
  on public.model_aliases(canonical_model_number);

create index if not exists product_lookup_logs_lookup_layer_idx
  on public.product_lookup_logs(lookup_layer, created_at desc);

create index if not exists product_lookup_logs_normalized_query_idx
  on public.product_lookup_logs(normalized_query_model_number, created_at desc);

alter table public.product_lookup_candidates enable row level security;
alter table public.model_aliases enable row level security;
alter table public.product_lookup_logs enable row level security;

drop policy if exists "product_lookup_candidates_service_manage" on public.product_lookup_candidates;
create policy "product_lookup_candidates_service_manage"
on public.product_lookup_candidates for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

drop policy if exists "model_aliases_service_manage" on public.model_aliases;
create policy "model_aliases_service_manage"
on public.model_aliases for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

drop policy if exists "product_lookup_logs_service_manage" on public.product_lookup_logs;
create policy "product_lookup_logs_service_manage"
on public.product_lookup_logs for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

insert into public.product_lookup_candidates (
  normalized_model_number,
  product_name,
  msrp,
  source,
  confidence,
  verification_state,
  hit_count,
  first_seen_at,
  last_seen_at,
  last_used_at,
  created_at
)
select
  public.normalize_model_number(normalized_model_number),
  product_name,
  msrp,
  coalesce(nullif(source, ''), 'model-ai'),
  confidence,
  'provisional',
  1,
  coalesce(last_verified_at, created_at, timezone('utc', now())),
  coalesce(last_verified_at, created_at, timezone('utc', now())),
  coalesce(last_verified_at, created_at, timezone('utc', now())),
  coalesce(created_at, timezone('utc', now()))
from public.product_catalog
where lower(coalesce(source, '')) = 'model-ai'
  and public.normalize_model_number(normalized_model_number) <> ''
on conflict (normalized_model_number) do update
set product_name = excluded.product_name,
    msrp = excluded.msrp,
    source = excluded.source,
    confidence = greatest(public.product_lookup_candidates.confidence, excluded.confidence),
    last_seen_at = greatest(public.product_lookup_candidates.last_seen_at, excluded.last_seen_at),
    last_used_at = greatest(public.product_lookup_candidates.last_used_at, excluded.last_used_at);
