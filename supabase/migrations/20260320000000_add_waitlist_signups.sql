create table if not exists public.waitlist_signups (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  source text not null default 'website_waitlist',
  referrer text,
  user_agent text,
  status text not null default 'pending'
    check (status in ('pending', 'invited', 'removed')),
  created_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists waitlist_signups_email_idx
  on public.waitlist_signups (email);

alter table public.waitlist_signups enable row level security;
