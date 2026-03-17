alter table public.org_members
  add column if not exists joined_at timestamptz not null default now();
