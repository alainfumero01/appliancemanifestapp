create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.invite_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  is_active boolean not null default true,
  usage_limit integer,
  usage_count integer not null default 0,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.product_catalog (
  normalized_model_number text primary key,
  product_name text not null,
  msrp numeric(10,2) not null check (msrp >= 0),
  source text not null,
  confidence double precision not null default 0,
  last_verified_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.manifests (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  load_reference text not null,
  status text not null default 'draft' check (status in ('draft', 'completed')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.manifest_items (
  id uuid primary key default gen_random_uuid(),
  manifest_id uuid not null references public.manifests(id) on delete cascade,
  model_number text not null,
  product_name text not null,
  msrp numeric(10,2) not null check (msrp >= 0),
  quantity integer not null default 1 check (quantity > 0),
  photo_path text,
  lookup_status text not null default 'pending',
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists manifests_owner_id_idx on public.manifests(owner_id);
create index if not exists manifest_items_manifest_id_idx on public.manifest_items(manifest_id);

alter table public.profiles enable row level security;
alter table public.invite_codes enable row level security;
alter table public.product_catalog enable row level security;
alter table public.manifests enable row level security;
alter table public.manifest_items enable row level security;

create policy "profiles_select_own"
on public.profiles for select
using (auth.uid() = id);

create policy "manifests_select_own"
on public.manifests for select
using (auth.uid() = owner_id);

create policy "manifests_insert_own"
on public.manifests for insert
with check (auth.uid() = owner_id);

create policy "manifests_update_own"
on public.manifests for update
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

create policy "manifest_items_select_owner"
on public.manifest_items for select
using (
  exists (
    select 1 from public.manifests m
    where m.id = manifest_items.manifest_id
      and m.owner_id = auth.uid()
  )
);

create policy "manifest_items_insert_owner"
on public.manifest_items for insert
with check (
  exists (
    select 1 from public.manifests m
    where m.id = manifest_items.manifest_id
      and m.owner_id = auth.uid()
  )
);

create policy "manifest_items_update_owner"
on public.manifest_items for update
using (
  exists (
    select 1 from public.manifests m
    where m.id = manifest_items.manifest_id
      and m.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.manifests m
    where m.id = manifest_items.manifest_id
      and m.owner_id = auth.uid()
  )
);

create policy "manifest_items_delete_owner"
on public.manifest_items for delete
using (
  exists (
    select 1 from public.manifests m
    where m.id = manifest_items.manifest_id
      and m.owner_id = auth.uid()
  )
);

create policy "catalog_shared_read"
on public.product_catalog for select
using (auth.role() = 'authenticated');

create policy "catalog_service_write"
on public.product_catalog for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create policy "invite_codes_service_manage"
on public.invite_codes for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

insert into storage.buckets (id, name, public)
values ('sticker-photos', 'sticker-photos', false)
on conflict (id) do nothing;
