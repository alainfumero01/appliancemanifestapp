alter table public.organizations
  add column if not exists app_store_product_id text,
  add column if not exists subscription_status text not null default 'free'
    check (subscription_status in ('free', 'active', 'expired', 'past_due', 'canceled')),
  add column if not exists subscription_expires_at timestamptz,
  add column if not exists billing_platform text not null default 'none'
    check (billing_platform in ('none', 'app_store')),
  add column if not exists trial_manifests_used integer not null default 0,
  add column if not exists trial_manifest_limit integer not null default 3;

create index if not exists invite_codes_org_id_idx on public.invite_codes(org_id);
