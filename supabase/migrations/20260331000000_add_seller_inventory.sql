alter table public.product_catalog
  add column if not exists brand text,
  add column if not exists appliance_category text;

alter table if exists public.product_lookup_candidates
  add column if not exists brand text,
  add column if not exists appliance_category text;

alter table public.manifest_items
  add column if not exists brand text,
  add column if not exists appliance_category text;

create table if not exists public.inventory_units (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  source_manifest_id uuid references public.manifests(id) on delete set null,
  source_manifest_item_id uuid references public.manifest_items(id) on delete set null,
  source_manifest_item_index integer,
  model_number text not null,
  product_name text not null,
  brand text,
  appliance_category text,
  msrp numeric(10,2) not null default 0 check (msrp >= 0),
  asking_price numeric(10,2) not null default 0 check (asking_price >= 0),
  cost_basis numeric(10,2) check (cost_basis is null or cost_basis >= 0),
  sold_price numeric(10,2) check (sold_price is null or sold_price >= 0),
  condition text not null default 'used'
    check (condition in ('new', 'used', 'refurbished', 'scratchAndDent')),
  status text not null default 'in_stock'
    check (status in ('in_stock', 'listed', 'reserved', 'sold')),
  photo_path text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  listed_at timestamptz,
  reserved_at timestamptz,
  sold_at timestamptz
);

create index if not exists inventory_units_org_id_idx
  on public.inventory_units(org_id);
create index if not exists inventory_units_status_idx
  on public.inventory_units(status);
create index if not exists inventory_units_category_idx
  on public.inventory_units(appliance_category);
create index if not exists inventory_units_model_idx
  on public.inventory_units(model_number);
create index if not exists inventory_units_source_manifest_idx
  on public.inventory_units(source_manifest_id);
create index if not exists inventory_units_source_item_idx
  on public.inventory_units(source_manifest_item_id);
create unique index if not exists inventory_units_source_item_key
  on public.inventory_units(source_manifest_item_id, source_manifest_item_index)
  where source_manifest_item_id is not null
    and source_manifest_item_index is not null;

create table if not exists public.manifest_inventory_links (
  id uuid primary key default gen_random_uuid(),
  manifest_id uuid not null references public.manifests(id) on delete cascade,
  manifest_item_id uuid not null references public.manifest_items(id) on delete cascade,
  inventory_unit_id uuid not null unique references public.inventory_units(id) on delete cascade,
  restore_status text not null
    check (restore_status in ('in_stock', 'listed', 'reserved', 'sold')),
  release_on_delete boolean not null default true,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists manifest_inventory_links_manifest_id_idx
  on public.manifest_inventory_links(manifest_id);
create index if not exists manifest_inventory_links_manifest_item_id_idx
  on public.manifest_inventory_links(manifest_item_id);

alter table public.inventory_units enable row level security;
alter table public.manifest_inventory_links enable row level security;

drop policy if exists "inventory_units_org_read" on public.inventory_units;
create policy "inventory_units_org_read"
on public.inventory_units for select
using (
  exists (
    select 1 from public.org_members om
    where om.org_id = inventory_units.org_id
      and om.user_id = auth.uid()
  )
);

drop policy if exists "inventory_units_org_insert" on public.inventory_units;
create policy "inventory_units_org_insert"
on public.inventory_units for insert
with check (
  exists (
    select 1 from public.org_members om
    where om.org_id = inventory_units.org_id
      and om.user_id = auth.uid()
  )
);

drop policy if exists "inventory_units_org_update" on public.inventory_units;
create policy "inventory_units_org_update"
on public.inventory_units for update
using (
  exists (
    select 1 from public.org_members om
    where om.org_id = inventory_units.org_id
      and om.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.org_members om
    where om.org_id = inventory_units.org_id
      and om.user_id = auth.uid()
  )
);

drop policy if exists "inventory_units_org_delete" on public.inventory_units;
create policy "inventory_units_org_delete"
on public.inventory_units for delete
using (
  exists (
    select 1 from public.org_members om
    where om.org_id = inventory_units.org_id
      and om.user_id = auth.uid()
  )
);

drop policy if exists "manifest_inventory_links_org_read" on public.manifest_inventory_links;
create policy "manifest_inventory_links_org_read"
on public.manifest_inventory_links for select
using (
  exists (
    select 1
    from public.manifests m
    join public.org_members om on om.org_id = m.org_id
    where m.id = manifest_inventory_links.manifest_id
      and om.user_id = auth.uid()
  )
);

drop policy if exists "manifest_inventory_links_org_insert" on public.manifest_inventory_links;
create policy "manifest_inventory_links_org_insert"
on public.manifest_inventory_links for insert
with check (
  exists (
    select 1
    from public.manifests m
    join public.org_members om on om.org_id = m.org_id
    where m.id = manifest_inventory_links.manifest_id
      and om.user_id = auth.uid()
  )
  and exists (
    select 1
    from public.manifest_items mi
    where mi.id = manifest_inventory_links.manifest_item_id
      and mi.manifest_id = manifest_inventory_links.manifest_id
  )
  and exists (
    select 1
    from public.inventory_units iu
    join public.manifests m on m.id = manifest_inventory_links.manifest_id
    where iu.id = manifest_inventory_links.inventory_unit_id
      and iu.org_id = m.org_id
  )
);

drop policy if exists "manifest_inventory_links_org_update" on public.manifest_inventory_links;
create policy "manifest_inventory_links_org_update"
on public.manifest_inventory_links for update
using (
  exists (
    select 1
    from public.manifests m
    join public.org_members om on om.org_id = m.org_id
    where m.id = manifest_inventory_links.manifest_id
      and om.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.manifests m
    join public.org_members om on om.org_id = m.org_id
    where m.id = manifest_inventory_links.manifest_id
      and om.user_id = auth.uid()
  )
);

drop policy if exists "manifest_inventory_links_org_delete" on public.manifest_inventory_links;
create policy "manifest_inventory_links_org_delete"
on public.manifest_inventory_links for delete
using (
  exists (
    select 1
    from public.manifests m
    join public.org_members om on om.org_id = m.org_id
    where m.id = manifest_inventory_links.manifest_id
      and om.user_id = auth.uid()
  )
);

drop policy if exists "manifest_inventory_links_service_manage" on public.manifest_inventory_links;
create policy "manifest_inventory_links_service_manage"
on public.manifest_inventory_links for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create or replace function public.touch_inventory_units_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists inventory_units_touch_updated_at on public.inventory_units;
create trigger inventory_units_touch_updated_at
  before update on public.inventory_units
  for each row execute procedure public.touch_inventory_units_updated_at();

create or replace function public.restore_inventory_from_manifest_link()
returns trigger
language plpgsql
as $$
begin
  if old.release_on_delete then
    update public.inventory_units
    set
      status = old.restore_status,
      reserved_at = null,
      updated_at = timezone('utc', now())
    where id = old.inventory_unit_id;
  end if;
  return old;
end;
$$;

drop trigger if exists manifest_inventory_links_restore_inventory on public.manifest_inventory_links;
create trigger manifest_inventory_links_restore_inventory
  after delete on public.manifest_inventory_links
  for each row execute procedure public.restore_inventory_from_manifest_link();
