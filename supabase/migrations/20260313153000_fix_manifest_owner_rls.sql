alter table public.manifests
  alter column owner_id set default auth.uid();
