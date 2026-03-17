-- Organizations: individual or enterprise subscriptions
create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  subscription_type text not null default 'individual'
    check (subscription_type in ('individual', 'enterprise')),
  -- Base seat limit: 1 for individual, 6 for enterprise (owner + 5 included codes)
  seat_limit integer not null default 1,
  -- Additional paid seats beyond the base (enterprise only, $5/seat)
  extra_seats integer not null default 0,
  -- Total scans used across the org (for free-tier tracking: 3 free scans)
  scan_count_used integer not null default 0,
  created_at timestamptz not null default timezone('utc', now())
);

-- Org membership: links users to their organization
create table if not exists public.org_members (
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default timezone('utc', now()),
  primary key (org_id, user_id)
);

-- Link profiles to their org
alter table public.profiles
  add column if not exists org_id uuid references public.organizations(id);

-- Session nonce: updated on every new login to invalidate concurrent sessions
alter table public.profiles
  add column if not exists session_nonce uuid;

-- Link invite codes to their org (enterprise codes belong to an org)
alter table public.invite_codes
  add column if not exists org_id uuid references public.organizations(id);

-- Link manifests to their org so all org members can view them
alter table public.manifests
  add column if not exists org_id uuid references public.organizations(id);

create index if not exists manifests_org_id_idx on public.manifests(org_id);
create index if not exists org_members_user_id_idx on public.org_members(user_id);

-- ─────────────────────────────────────────────────
-- RLS: Organizations
-- ─────────────────────────────────────────────────
alter table public.organizations enable row level security;

create policy "orgs_member_read"
on public.organizations for select
using (
  exists (
    select 1 from public.org_members om
    where om.org_id = organizations.id
      and om.user_id = auth.uid()
  )
);

-- ─────────────────────────────────────────────────
-- RLS: Org Members
-- ─────────────────────────────────────────────────
alter table public.org_members enable row level security;

create policy "org_members_same_org_read"
on public.org_members for select
using (
  exists (
    select 1 from public.org_members om
    where om.org_id = org_members.org_id
      and om.user_id = auth.uid()
  )
);

-- ─────────────────────────────────────────────────
-- RLS: Manifests — expand SELECT to all org members
-- ─────────────────────────────────────────────────
drop policy if exists "manifests_select_own" on public.manifests;

create policy "manifests_select_org"
on public.manifests for select
using (
  auth.uid() = owner_id
  or (
    org_id is not null
    and exists (
      select 1 from public.org_members om
      where om.org_id = manifests.org_id
        and om.user_id = auth.uid()
    )
  )
);

-- ─────────────────────────────────────────────────
-- RLS: Manifest Items — expand SELECT to org members
-- ─────────────────────────────────────────────────
drop policy if exists "manifest_items_select_owner" on public.manifest_items;

create policy "manifest_items_select_org"
on public.manifest_items for select
using (
  exists (
    select 1 from public.manifests m
    where m.id = manifest_items.manifest_id
      and (
        m.owner_id = auth.uid()
        or (
          m.org_id is not null
          and exists (
            select 1 from public.org_members om
            where om.org_id = m.org_id
              and om.user_id = auth.uid()
          )
        )
      )
  )
);

-- ─────────────────────────────────────────────────
-- RLS: Profiles — allow users to update their own row
--       (needed for nonce updates via service role in edge functions)
-- ─────────────────────────────────────────────────
create policy "profiles_update_own"
on public.profiles for update
using (auth.uid() = id)
with check (auth.uid() = id);
